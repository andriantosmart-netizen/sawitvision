import 'dart:typed_data';

import '../models/scan_result.dart';
import 'detection_service.dart';

/// Dilempar saat model custom belum tersedia. UI menangkap ini dan
/// mengarahkan user untuk pakai mode CV Klasik dulu (lihat
/// lib/screens/result_screen.dart — sudah ada fallback otomatisnya).
class ModelNotAvailableException implements Exception {
  final String message;
  ModelNotAvailableException(this.message);
  @override
  String toString() => message;
}

/// Mesin deteksi berbasis model TFLite hasil training custom (mis. YOLOv8n
/// yang dilatih dari foto janjang & brondol lapangan lalu di-export ke
/// TFLite — lihat `training_pipeline/`).
///
/// STATUS SEMENTARA — DINONAKTIFKAN:
/// Dependency `tflite_flutter` sengaja dilepas dari pubspec.yaml karena
/// versi native TensorFlow Lite yang dibawanya bentrok "namespace" satu
/// sama lain di Android Gradle Plugin terbaru (error build: "Namespace
/// 'org.tensorflow.lite' is used in multiple modules and/or libraries"),
/// masalah upstream di paket itu sendiri. Karena belum ada model .tflite
/// hasil training juga (belum ada dataset foto lapangan), fitur ini memang
/// belum terpakai — jadi class ini disederhanakan menjadi stub yang selalu
/// melempar [ModelNotAvailableException], dan UI otomatis fallback ke
/// [CvDetectionService] (mode default, tetap berfungsi penuh).
///
/// Untuk mengaktifkan kembali nanti (setelah punya model + tflite_flutter
/// versi yang sudah memperbaiki konflik ini, atau ganti ke package TFLite
/// lain):
///   1. Tambahkan lagi dependency tflite_flutter (atau alternatifnya) di
///      pubspec.yaml.
///   2. Kembalikan logic load-model & inference (decode gambar, resize ke
///      [inputSize], jalankan interpreter, parse output YOLO, dst.) di
///      method [detect] — lihat riwayat git file ini untuk versi lengkap
///      sebelumnya sebagai referensi.
class TfliteDetectionService implements DetectionService {
  final String modelAsset;
  final String labelsAsset;
  final int inputSize;
  final double confidenceThreshold;
  final double iouThreshold;

  TfliteDetectionService({
    this.modelAsset = 'assets/models/sawit_detector.tflite',
    this.labelsAsset = 'assets/labels/labels.txt',
    this.inputSize = 320,
    this.confidenceThreshold = 0.4,
    this.iouThreshold = 0.45,
  });

  @override
  String get engineName => 'Model Custom (TFLite)';

  @override
  Future<DetectionOutput> detect({
    required Uint8List imageBytes,
    required ScanMode mode,
  }) async {
    throw ModelNotAvailableException(
      'Mode Model Custom (TFLite) sedang dinonaktifkan sementara di build '
      'ini (konflik teknis pada paket tflite_flutter). Aplikasi otomatis '
      'memakai mode CV Klasik. Latih model lewat training_pipeline/ dan '
      'aktifkan kembali fitur ini sesuai catatan di bagian atas file '
      'lib/services/tflite_detection_service.dart.',
    );
  }

  void dispose() {}
}
