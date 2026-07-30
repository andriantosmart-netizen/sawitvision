import 'dart:typed_data';

import '../models/scan_result.dart';

/// Ringkasan hasil deteksi untuk satu foto.
class DetectionOutput {
  /// Semua objek yang berhasil dideteksi (untuk digambar sebagai overlay).
  final List<DetectedObject> objects;

  /// Jumlah objek yang benar-benar terlihat di foto.
  final int visibleCount;

  /// Estimasi jumlah total (untuk mode brondol, sudah memperhitungkan
  /// kemungkinan brondol yang tertutup/tumpuk tidak terlihat kamera).
  /// Untuk mode janjang, nilainya sama dengan [visibleCount].
  final int estimatedTotalCount;

  /// Rata-rata confidence dari objek yang terdeteksi (0-1).
  final double avgConfidence;

  const DetectionOutput({
    required this.objects,
    required this.visibleCount,
    required this.estimatedTotalCount,
    required this.avgConfidence,
  });

  static const empty = DetectionOutput(
    objects: [],
    visibleCount: 0,
    estimatedTotalCount: 0,
    avgConfidence: 0,
  );
}

/// Kontrak untuk semua mesin deteksi (CV klasik maupun model TFLite custom).
/// UI (scan_screen/result_screen) hanya bergantung pada interface ini,
/// sehingga mengganti mesin deteksi tidak perlu mengubah kode UI.
abstract class DetectionService {
  Future<DetectionOutput> detect({
    required Uint8List imageBytes,
    required ScanMode mode,
  });

  /// Nama mesin deteksi, ditampilkan di Settings/Result screen.
  String get engineName;
}
