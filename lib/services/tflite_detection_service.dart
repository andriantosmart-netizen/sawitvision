import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/scan_result.dart';
import 'detection_service.dart';

/// Dilempar saat model custom belum tersedia di assets/models/.
/// UI menangkap ini dan mengarahkan user untuk pakai mode CV Klasik dulu.
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
/// Ini adalah wrapper generik untuk model deteksi objek 1-stage bergaya
/// YOLO dengan output tensor [1, num_boxes, 5 + num_classes]
/// (x, y, w, h, objectness, ...class_scores). Sesuaikan [inputSize],
/// path model/label, dan [_parseYoloOutput] jika arsitektur/format model
/// Anda berbeda dari asumsi ini.
///
/// Selama `assets/models/sawit_detector.tflite` belum ada, service ini
/// akan melempar [ModelNotAvailableException] — aplikasi tetap berjalan
/// normal memakai [CvDetectionService] sebagai default.
class TfliteDetectionService implements DetectionService {
  final String modelAsset;
  final String labelsAsset;
  final int inputSize;
  final double confidenceThreshold;
  final double iouThreshold;

  Interpreter? _interpreter;
  List<String>? _labels;

  TfliteDetectionService({
    this.modelAsset = 'assets/models/sawit_detector.tflite',
    this.labelsAsset = 'assets/labels/labels.txt',
    this.inputSize = 320,
    this.confidenceThreshold = 0.4,
    this.iouThreshold = 0.45,
  });

  @override
  String get engineName => 'Model Custom (TFLite)';

  Future<void> _ensureLoaded() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset(modelAsset);
    } catch (e) {
      throw ModelNotAvailableException(
        'Model custom belum ditemukan di "$modelAsset". '
        'Latih model lewat training_pipeline/ terlebih dahulu, lalu taruh '
        'file .tflite di assets/models/ dan aktifkan kembali mode ini. '
        '(detail: $e)',
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

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return DetectionOutput.empty;

    final resized = img.copyResize(decoded, width: inputSize, height: inputSize);

    // Normalisasi ke Float32 [1, inputSize, inputSize, 3], range 0-1.
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        }),
      ),
    );

    // TODO: sesuaikan shape output dengan hasil export model Anda.
    // Asumsi default: [1, N, 5 + numClasses] gaya YOLOv8.
    final outputShape = interpreter.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    interpreter.run(input, output);

    final rawBoxes = _parseYoloOutput(output[0]);
    final filtered = _nonMaxSuppression(rawBoxes, iouThreshold);

    final objects = filtered
        .map((b) => DetectedObject(
              label: (_labels != null && b.classId < _labels!.length)
                  ? _labels![b.classId]
                  : (mode == ScanMode.brondol ? 'brondol' : 'janjang'),
              x: (b.cx - b.w / 2).clamp(0.0, 1.0),
              y: (b.cy - b.h / 2).clamp(0.0, 1.0),
              width: b.w,
              height: b.h,
              confidence: b.score,
            ))
        .toList();

    final visibleCount = objects.length;
    final avgConfidence = objects.isEmpty
        ? 0.0
        : objects.map((o) => o.confidence).reduce((a, b) => a + b) /
            objects.length;

    return DetectionOutput(
      objects: objects,
      visibleCount: visibleCount,
      // Model custom idealnya sudah dilatih untuk mengenali brondol yang
      // tumpuk/tertutup sebagian, jadi tanpa faktor koreksi tambahan.
      estimatedTotalCount: visibleCount,
      avgConfidence: avgConfidence,
    );
  }

  List<_RawBox> _parseYoloOutput(List<List<double>> preds) {
    final boxes = <_RawBox>[];
    for (final row in preds) {
      if (row.length < 5) continue;
      final cx = row[0];
      final cy = row[1];
      final w = row[2];
      final h = row[3];
      final objectness = row[4];

      int bestClass = 0;
      double bestScore = 0;
      for (int c = 5; c < row.length; c++) {
        if (row[c] > bestScore) {
          bestScore = row[c];
          bestClass = c - 5;
        }
      }
      final score = objectness * (bestScore == 0 ? 1 : bestScore);
      if (score >= confidenceThreshold) {
        boxes.add(_RawBox(cx: cx, cy: cy, w: w, h: h, score: score, classId: bestClass));
      }
    }
    return boxes;
  }

  List<_RawBox> _nonMaxSuppression(List<_RawBox> boxes, double iouThresh) {
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_RawBox>[];
    for (final box in boxes) {
      final overlaps = kept.any((k) => _iou(box, k) > iouThresh);
      if (!overlaps) kept.add(box);
    }
    return kept;
  }

  double _iou(_RawBox a, _RawBox b) {
    final ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2;
    final ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2;
    final bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2;
    final bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2;

    final interX1 = math.max(ax1, bx1);
    final interY1 = math.max(ay1, by1);
    final interX2 = math.min(ax2, bx2);
    final interY2 = math.min(ay2, by2);

    final interArea =
        math.max(0.0, interX2 - interX1) * math.max(0.0, interY2 - interY1);
    final unionArea = a.w * a.h + b.w * b.h - interArea;
    return unionArea <= 0 ? 0 : interArea / unionArea;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

class _RawBox {
  final double cx, cy, w, h, score;
  final int classId;
  _RawBox({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    required this.score,
    required this.classId,
  });
}
