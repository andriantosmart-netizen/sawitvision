import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/scan_result.dart';
import 'detection_service.dart';

/// Dilempar saat model custom belum tersedia / gagal dimuat. UI menangkap
/// ini dan mengarahkan user untuk pakai mode CV Klasik dulu (lihat
/// lib/screens/result_screen.dart — sudah ada fallback otomatisnya).
class ModelNotAvailableException implements Exception {
  final String message;
  ModelNotAvailableException(this.message);
  @override
  String toString() => message;
}

/// Mesin deteksi berbasis model TFLite hasil training custom (YOLO26n,
/// dilatih dari foto janjang & brondol lapangan lewat `training_pipeline/`,
/// lihat juga `assets/models/README.md`).
///
/// Cara kerja & keputusan implementasi (dicatat di sini karena beberapa di
/// antaranya TIDAK OBVIOUS dan sempat diverifikasi manual lewat Python
/// sebelum ditulis ke Dart -- lihat riwayat sesi 2026-08-03):
///
/// 1. Model diexport dari Ultralytics dalam format LiteRT/TFLite dengan
///    input **NCHW** `[1, 3, 640, 640]` float32 (channel-first, BUKAN
///    channel-last/NHWC seperti kebanyakan tutorial TFLite lain) -- ini
///    dicek langsung lewat `interpreter.get_input_details()` di Python,
///    bukan diasumsikan.
/// 2. Preprocessing WAJIB pakai **letterbox** (resize proporsional + padding
///    abu-abu di sisi pendek, BUKAN stretch-resize biasa) -- terbukti lewat
///    pengujian langsung: stretch-resize pada foto landscape/portrait ekstrem
///    (umum dari kamera HP, bukan persegi) membuat jumlah objek yang
///    terdeteksi jauh lebih sedikit (mis. 6 vs 16 deteksi pada foto yang
///    sama), karena model dilatih dengan letterbox oleh Ultralytics.
/// 3. Output berbentuk `[1, 300, 6]` -- **NMS sudah dilakukan di dalam model
///    saat export** (format "end-to-end" Ultralytics), jadi TIDAK PERLU
///    implementasi NMS manual lagi di Dart. Tiap baris = `[x1, y1, x2, y2,
///    confidence, class_id]` dalam koordinat piksel kanvas 640x640
///    (sebelum di-unletterbox ke koordinat foto asli). Baris "kosong" (slot
///    sisa dari 300, karena objek yang terdeteksi biasanya jauh lebih
///    sedikit dari 300) punya confidence sangat rendah (~0.001) sehingga
///    otomatis tersaring oleh [confidenceThreshold].
///
/// CATATAN JUJUR: kode ini ditulis & di-review manual, TAPI belum sempat
/// di-build/dites langsung di HP/emulator (lingkungan kerja Claude tidak
/// punya SDK Flutter/Android). Build pertama lewat Codemagic sebaiknya
/// dianggap sebagai uji coba pertama kode ini -- kalau ada error build atau
/// hasil deteksi yang aneh di lapangan, laporkan agar bisa diperbaiki.
class TfliteDetectionService implements DetectionService {
  final String modelAsset;
  final String labelsAsset;
  final int inputSize;
  final double confidenceThreshold;
  final double occlusionFactor;

  TfliteDetectionService({
    this.modelAsset = 'assets/models/sawit_detector.tflite',
    this.labelsAsset = 'assets/labels/labels.txt',
    this.inputSize = 640, // HARUS sama dengan imgsz saat training/export
    this.confidenceThreshold = 0.35,
    this.occlusionFactor = 1.4,
  });

  // Interpreter & label di-cache statis supaya tidak reload model dari
  // asset setiap kali user scan foto (loading model relatif berat).
  static Interpreter? _interpreter;
  static List<String>? _labels;
  static String? _loadedModelAsset;

  @override
  String get engineName => 'Model Custom (TFLite) — YOLO26n';

  Future<void> _ensureLoaded() async {
    if (_interpreter != null &&
        _labels != null &&
        _loadedModelAsset == modelAsset) {
      return;
    }
    try {
      _interpreter = await Interpreter.fromAsset(modelAsset);
      _loadedModelAsset = modelAsset;
    } catch (e) {
      _interpreter = null;
      _loadedModelAsset = null;
      throw ModelNotAvailableException(
        'Gagal memuat model TFLite dari $modelAsset ($e). Pastikan file '
        'sudah ada di assets/models/ dan terdaftar di pubspec.yaml, lalu '
        'jalankan "flutter pub get" ulang.',
      );
    }

    try {
      final raw = await rootBundle.loadString(labelsAsset);
      _labels = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (e) {
      _interpreter = null;
      _loadedModelAsset = null;
      throw ModelNotAvailableException(
        'Gagal memuat daftar label dari $labelsAsset ($e).',
      );
    }
  }

  @override
  Future<DetectionOutput> detect({
    required Uint8List imageBytes,
    required ScanMode mode,
  }) async {
    await _ensureLoaded();
    final interpreter = _interpreter!;
    final labels = _labels!;

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return DetectionOutput.empty;

    final origW = decoded.width;
    final origH = decoded.height;

    // --- 1. Letterbox resize ke inputSize x inputSize (lihat catatan kelas
    // di atas kenapa ini wajib, bukan stretch-resize biasa) ---
    final scale = math.min(inputSize / origW, inputSize / origH);
    final newW = (origW * scale).round().clamp(1, inputSize);
    final newH = (origH * scale).round().clamp(1, inputSize);
    final resized = img.copyResize(
      decoded,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.average,
    );

    final padLeft = (inputSize - newW) ~/ 2;
    final padTop = (inputSize - newH) ~/ 2;

    final canvas = img.Image(width: inputSize, height: inputSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: padLeft, dstY: padTop);

    // --- 2. Susun tensor input NCHW [1, 3, 640, 640], normalisasi 0-1 ---
    final input = [
      List.generate(
        3,
        (c) => List.generate(
          inputSize,
          (y) => List.generate(inputSize, (x) {
            final p = canvas.getPixel(x, y);
            final v = c == 0 ? p.r : (c == 1 ? p.g : p.b);
            return v / 255.0;
          }),
        ),
      ),
    ];

    // --- 3. Jalankan model. Output [1, 300, 6], NMS sudah bawaan model. ---
    final output = [
      List.generate(300, (_) => List<double>.filled(6, 0.0)),
    ];
    interpreter.run(input, output);

    // Kelas yang relevan untuk mode layar ini. `janjang_kosong` (tandan
    // kosong/sudah rontok) SENGAJA belum dihitung di mode manapun untuk
    // sekarang -- itu bukan TBS yang dipanen maupun brondol, jadi ikut
    // menghitungnya akan membuat jumlah di layar hasil jadi salah. Kalau
    // nanti mau dimunculkan sebagai info terpisah (mis. badge "N tandan
    // kosong terdeteksi"), tambahkan field baru di DetectionOutput, jangan
    // dicampur ke visibleCount/estimatedTotalCount di sini.
    final wantedLabel = mode == ScanMode.brondol ? 'brondol' : 'janjang';

    final objects = <DetectedObject>[];
    for (final row in output[0]) {
      final conf = row[4];
      if (conf < confidenceThreshold) continue;
      final classId = row[5].round();
      if (classId < 0 || classId >= labels.length) continue;
      if (labels[classId] != wantedLabel) continue;

      // --- 4. Un-letterbox: balik koordinat dari kanvas 640x640 ke foto asli ---
      final x1 = ((row[0] - padLeft) / scale).clamp(0.0, origW.toDouble());
      final y1 = ((row[1] - padTop) / scale).clamp(0.0, origH.toDouble());
      final x2 = ((row[2] - padLeft) / scale).clamp(0.0, origW.toDouble());
      final y2 = ((row[3] - padTop) / scale).clamp(0.0, origH.toDouble());
      if (x2 <= x1 || y2 <= y1) continue;

      objects.add(DetectedObject(
        label: wantedLabel,
        x: x1 / origW,
        y: y1 / origH,
        width: (x2 - x1) / origW,
        height: (y2 - y1) / origH,
        confidence: conf.toDouble(),
      ));
    }

    final visibleCount = objects.length;
    // Sama seperti CvDetectionService: untuk mode brondol, kalikan dengan
    // occlusionFactor untuk mengestimasi brondol yang tertutup/tumpuk & tidak
    // terlihat kamera. Mode janjang tidak dikoreksi (tiap tandan biasanya
    // terlihat penuh di foto TPH).
    final estimatedTotal = mode == ScanMode.brondol
        ? (visibleCount * occlusionFactor).round()
        : visibleCount;
    final avgConfidence = objects.isEmpty
        ? 0.0
        : objects.map((o) => o.confidence).reduce((a, b) => a + b) /
            objects.length;

    return DetectionOutput(
      objects: objects,
      visibleCount: visibleCount,
      estimatedTotalCount: estimatedTotal,
      avgConfidence: avgConfidence,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _labels = null;
    _loadedModelAsset = null;
  }
}
