import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../models/scan_result.dart';
import 'detection_service.dart';

/// Mesin deteksi berbasis Computer Vision klasik (color thresholding +
/// connected-component/blob detection). Tidak butuh model AI/training,
/// sehingga aplikasi langsung bisa dipakai sejak hari pertama walau belum
/// ada dataset foto sawit yang berlabel.
///
/// Cara kerja singkat:
/// 1. Foto diperkecil ke lebar tetap agar proses cepat di HP low-end.
/// 2. Setiap piksel diklasifikasi berdasarkan warna: oranye-kemerahan khas
///    brondol/buah matang, atau coklat-kehitaman khas kulit janjang.
/// 2. Piksel yang cocok dikelompokkan jadi "blob" lewat flood fill.
/// 3. Blob difilter berdasarkan ukuran (relatif terhadap luas foto) supaya
///    noise kecil atau area besar (mis. tanah/daun) tidak ikut terhitung.
/// 4. Untuk mode brondol, jumlah blob yang terlihat dikalikan
///    [occlusionFactor] untuk mengestimasi brondol yang tertutup/tumpuk.
///
/// Akurasi mode ini sangat dipengaruhi pencahayaan & sudut foto — cocok
/// sebagai estimasi lapangan cepat. Untuk akurasi lebih tinggi, latih model
/// custom lewat `training_pipeline/` lalu pindah ke [TfliteDetectionService].
class CvDetectionService implements DetectionService {
  final int workingWidth;
  final double minBlobAreaRatioJanjang;
  final double maxBlobAreaRatioJanjang;
  final double minBlobAreaRatioBrondol;
  final double maxBlobAreaRatioBrondol;
  final double occlusionFactor;

  const CvDetectionService({
    this.workingWidth = 480,
    this.minBlobAreaRatioJanjang = 0.01,
    this.maxBlobAreaRatioJanjang = 0.35,
    this.minBlobAreaRatioBrondol = 0.00015,
    this.maxBlobAreaRatioBrondol = 0.01,
    this.occlusionFactor = 1.4,
  });

  @override
  String get engineName => 'CV Klasik (color + blob detection)';

  @override
  Future<DetectionOutput> detect({
    required Uint8List imageBytes,
    required ScanMode mode,
  }) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return DetectionOutput.empty;

    final aspect = decoded.height / decoded.width;
    final resized = img.copyResize(
      decoded,
      width: workingWidth,
      height: (workingWidth * aspect).round(),
      interpolation: img.Interpolation.average,
    );

    final w = resized.width;
    final h = resized.height;
    final visited = List<bool>.filled(w * h, false);

    bool isMatch(int x, int y) {
      final p = resized.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      return mode == ScanMode.brondol
          ? _isRipeOrange(r, g, b)
          : _isJanjangHusk(r, g, b);
    }

    final minAreaPx = w *
        h *
        (mode == ScanMode.brondol
            ? minBlobAreaRatioBrondol
            : minBlobAreaRatioJanjang);
    final maxAreaPx = w *
        h *
        (mode == ScanMode.brondol
            ? maxBlobAreaRatioBrondol
            : maxBlobAreaRatioJanjang);

    final objects = <DetectedObject>[];

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        if (visited[idx]) continue;
        visited[idx] = true;
        if (!isMatch(x, y)) continue;

        // Flood fill (BFS iteratif, tanpa rekursi agar aman untuk blob besar).
        final stack = <int>[idx];
        int minX = x, maxX = x, minY = y, maxY = y, count = 0;

        while (stack.isNotEmpty) {
          final cur = stack.removeLast();
          final cy = cur ~/ w;
          final cx = cur % w;
          count++;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;

          for (final d in const [
            [1, 0],
            [-1, 0],
            [0, 1],
            [0, -1]
          ]) {
            final nx = cx + d[0];
            final ny = cy + d[1];
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
            final nIdx = ny * w + nx;
            if (visited[nIdx]) continue;
            visited[nIdx] = true;
            if (isMatch(nx, ny)) stack.add(nIdx);
          }
        }

        if (count >= minAreaPx && count <= maxAreaPx) {
          final bboxW = (maxX - minX + 1) / w;
          final bboxH = (maxY - minY + 1) / h;
          // Solidity: rasio area blob terhadap area bounding box.
          // Blob bulat/solid (bukan garis noise tipis) → confidence lebih tinggi.
          final bboxAreaPx = (maxX - minX + 1) * (maxY - minY + 1);
          final solidity = bboxAreaPx > 0 ? count / bboxAreaPx : 0.0;
          final confidence = solidity.clamp(0.3, 0.95);

          objects.add(DetectedObject(
            label: mode == ScanMode.brondol ? 'brondol' : 'janjang',
            x: minX / w,
            y: minY / h,
            width: bboxW,
            height: bboxH,
            confidence: confidence,
          ));
        }
      }
    }

    final visibleCount = objects.length;
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

  /// Warna oranye-kemerahan khas brondol/buah sawit matang.
  bool _isRipeOrange(int r, int g, int b) {
    if (r < 130) return false;
    if (r - b < 40) return false;
    if (g > r) return false;
    if (b > 120) return false;
    return true;
  }

  /// Warna coklat-kehitaman khas kulit janjang (campuran buah matang &
  /// belum matang dalam satu tandan menghasilkan tekstur gelap-oranye).
  bool _isJanjangHusk(int r, int g, int b) {
    final brightness = (r + g + b) / 3;
    if (brightness > 160) return false; // terlalu terang, kemungkinan latar
    final isDarkBrown = r > g && r > 40 && brightness < 140;
    final isRipeOrange = _isRipeOrange(r, g, b);
    return isDarkBrown || isRipeOrange;
  }
}
