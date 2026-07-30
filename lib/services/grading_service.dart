import '../models/fraksi.dart';
import '../services/detection_service.dart';

/// Hasil perhitungan grading untuk satu deteksi brondol.
class GradingResult {
  final int estimasiBrondol;
  final int referensiTotalBrondol;
  final double persenBrondol;
  final Fraksi fraksi;

  const GradingResult({
    required this.estimasiBrondol,
    required this.referensiTotalBrondol,
    required this.persenBrondol,
    required this.fraksi,
  });
}

/// Menerjemahkan hasil deteksi mentah (jumlah brondol) menjadi persentase
/// kematangan & fraksi, mengikuti standar industri kelapa sawit
/// (lihat docs/ARSITEKTUR.md bagian 3).
class GradingService {
  final FraksiThresholds thresholds;

  const GradingService({this.thresholds = const FraksiThresholds()});

  GradingResult hitungGrading({
    required DetectionOutput deteksi,
    required UkuranJanjang ukuranJanjang,
    int? referensiTotalManual,
  }) {
    final referensiTotal =
        referensiTotalManual ?? ukuranJanjang.defaultTotalBrondol;
    final estimasi = deteksi.estimatedTotalCount;

    final persen =
        referensiTotal <= 0 ? 0.0 : (estimasi / referensiTotal) * 100.0;
    final fraksi = thresholds.hitungFraksi(persen);

    return GradingResult(
      estimasiBrondol: estimasi,
      referensiTotalBrondol: referensiTotal,
      persenBrondol: persen,
      fraksi: fraksi,
    );
  }
}
