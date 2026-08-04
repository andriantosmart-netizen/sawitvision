import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Coba tebak batas objek di sekitar titik yang di-DOUBLE-TAP, lewat
/// "region growing" berbasis kemiripan warna terhadap piksel yang ditap
/// (BUKAN warna tetap oranye/coklat seperti di CvDetectionService -- di
/// sini "diseeding" dari titik tap itu sendiri, supaya bisa dipakai untuk
/// kelas objek apapun: janjang/brondol/janjang kosong).
///
/// SENGAJA dibatasi ke jendela lokal kecil di sekitar titik tap (BUKAN
/// seluruh foto) supaya cepat & tidak bikin lag walau foto aslinya
/// beresolusi besar (foto kamera HP modern bisa 12MP+) -- ini menjawab
/// keluhan lag di percobaan sebelumnya (yang penyebabnya beda, tapi kita
/// tetap hati-hati jangan sampai nambah beban baru di titik lain).
///
/// Return null kalau region yang tumbuh terlalu kecil (noise) atau
/// menyentuh tepi jendela pencarian (kemungkinan besar background seragam
/// ikut "termakan", bukan objek yang berdiri sendiri) -- pemanggil
/// sebaiknya jatuh ke kotak ukuran default kalau ini terjadi. Ini best
/// effort/heuristik, bukan deteksi objek sungguhan -- untuk itu pakai mode
/// "Model Custom (TFLite)".
Rect? autoFitBoxAt({
  required img.Image source,
  required double tapFracX,
  required double tapFracY,
}) {
  final w = source.width;
  final h = source.height;
  if (w < 4 || h < 4) return null;

  final cx = (tapFracX * w).round().clamp(0, w - 1);
  final cy = (tapFracY * h).round().clamp(0, h - 1);

  // Jendela kerja lokal di sekitar titik tap -- maksimal ~18% dari sisi
  // terpendek foto di tiap arah, dan dibatasi juga ke piksel absolut (220px)
  // supaya foto sangat besar tetap cepat diproses.
  final windowRadius = math.min((math.min(w, h) * 0.18).round(), 220);
  final left = (cx - windowRadius).clamp(0, w - 1);
  final top = (cy - windowRadius).clamp(0, h - 1);
  final right = (cx + windowRadius).clamp(0, w - 1);
  final bottom = (cy + windowRadius).clamp(0, h - 1);
  final winW = right - left + 1;
  final winH = bottom - top + 1;

  final seed = source.getPixel(cx, cy);
  final seedR = seed.r.toInt();
  final seedG = seed.g.toInt();
  final seedB = seed.b.toInt();

  // Ambang kemiripan warna -- cukup longgar untuk menoleransi variasi
  // pencahayaan ringan di permukaan objek yang sama, tapi cukup ketat untuk
  // (biasanya) berhenti di tepi objek.
  const threshold = 42;
  const thresholdSq = threshold * threshold;
  bool isSimilar(int x, int y) {
    final p = source.getPixel(x, y);
    final dr = p.r.toInt() - seedR;
    final dg = p.g.toInt() - seedG;
    final db = p.b.toInt() - seedB;
    return (dr * dr + dg * dg + db * db) <= thresholdSq;
  }

  final visited = List<bool>.filled(winW * winH, false);
  int localIdx(int x, int y) => (y - top) * winW + (x - left);

  // Stack pakai indeks ABSOLUT (y * w + x, memakai lebar foto ASLI) supaya
  // gampang dibalik ke koordinat x/y tanpa ambigu dengan indeks jendela.
  final stack = <int>[cy * w + cx];
  visited[localIdx(cx, cy)] = true;
  int minX = cx, maxX = cx, minY = cy, maxY = cy, count = 0;
  bool touchedEdge = false;

  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    final curY = cur ~/ w;
    final curX = cur % w;
    count++;
    if (curX < minX) minX = curX;
    if (curX > maxX) maxX = curX;
    if (curY < minY) minY = curY;
    if (curY > maxY) maxY = curY;
    if (curX == left || curX == right || curY == top || curY == bottom) {
      touchedEdge = true;
    }

    for (final d in const [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ]) {
      final nx = curX + d[0];
      final ny = curY + d[1];
      if (nx < left || nx > right || ny < top || ny > bottom) continue;
      final li = localIdx(nx, ny);
      if (visited[li]) continue;
      visited[li] = true;
      if (isSimilar(nx, ny)) stack.add(ny * w + nx);
    }
  }

  // Region terlalu kecil (noise) atau menyentuh tepi jendela pencarian
  // (kemungkinan besar background seragam ikut termakan, atau objeknya
  // lebih besar dari jendela sehingga hasilnya tidak lengkap) -- tidak
  // yakin, biar pemanggil pakai ukuran default saja.
  final windowArea = winW * winH;
  final areaFrac = windowArea > 0 ? count / windowArea : 1.0;
  if (count < 30 || areaFrac > 0.85 || touchedEdge) return null;

  // Padding tipis supaya kotak tidak terlalu pas/ketat di tepi objek.
  const pad = 0.12; // 12% dari lebar/tinggi blob
  final bw = (maxX - minX + 1).toDouble();
  final bh = (maxY - minY + 1).toDouble();
  final padX = bw * pad;
  final padY = bh * pad;

  final rx1 = (minX - padX).clamp(0.0, w.toDouble());
  final ry1 = (minY - padY).clamp(0.0, h.toDouble());
  final rx2 = (maxX + 1 + padX).clamp(0.0, w.toDouble());
  final ry2 = (maxY + 1 + padY).clamp(0.0, h.toDouble());
  if (rx2 <= rx1 || ry2 <= ry1) return null;

  return Rect.fromLTRB(rx1 / w, ry1 / h, rx2 / w, ry2 / h);
}
