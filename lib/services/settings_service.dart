import 'package:shared_preferences/shared_preferences.dart';

import '../models/fraksi.dart';

/// Mode mesin deteksi yang aktif.
enum DetectionEngine { cvKlasik, tflite }

/// Semua preferensi/kalibrasi disimpan lokal lewat SharedPreferences —
/// tidak ada sinkronisasi ke server.
class SettingsService {
  static const _kEngine = 'detection_engine';
  static const _kOcclusionFactor = 'occlusion_factor';
  static const _kFraksiThresholds = 'fraksi_thresholds';
  static const _kDefaultUkuran = 'default_ukuran_janjang';
  static const _kTfliteConfidence = 'tflite_confidence_threshold';

  // Sinkronisasi cloud (opsional)
  static const _kCompanyId = 'sync_company_id';
  static const _kCompanyKode = 'sync_company_kode';
  static const _kWorkerName = 'sync_worker_name';
  static const _kAutoSync = 'sync_auto_enabled';
  static const _kLastSyncAt = 'sync_last_at';

  Future<DetectionEngine> getEngine() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kEngine) ?? DetectionEngine.cvKlasik.name;
    return DetectionEngine.values.byName(value);
  }

  Future<void> setEngine(DetectionEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEngine, engine.name);
  }

  Future<double> getOcclusionFactor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kOcclusionFactor) ?? 1.4;
  }

  Future<void> setOcclusionFactor(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kOcclusionFactor, value);
  }

  /// Ambang confidence minimum untuk mode "Model Custom (TFLite)" -- deteksi
  /// di bawah nilai ini dibuang sebelum ditampilkan/dihitung. Default 0.35
  /// dipilih berdasarkan pengujian nyata model YOLO26n hasil training
  /// pertama (2026-08-03): sebagian besar deteksi asli tersebar di kisaran
  /// confidence 0.3-0.9an, sedangkan di bawah ~0.3 mulai banyak deteksi palsu
  /// (mis. menandai perkakas/tanah kosong sebagai janjang). Sesuaikan di sini
  /// kalau lapangan menemukan terlalu banyak/kurang deteksi.
  Future<double> getTfliteConfidenceThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kTfliteConfidence) ?? 0.35;
  }

  Future<void> setTfliteConfidenceThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTfliteConfidence, value);
  }

  Future<UkuranJanjang> getDefaultUkuran() async {
    final prefs = await SharedPreferences.getInstance();
    final value =
        prefs.getString(_kDefaultUkuran) ?? UkuranJanjang.sedang.name;
    return UkuranJanjang.values.byName(value);
  }

  Future<void> setDefaultUkuran(UkuranJanjang ukuran) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultUkuran, ukuran.name);
  }

  Future<FraksiThresholds> getFraksiThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFraksiThresholds);
    if (raw == null || raw.length != 6) return const FraksiThresholds();
    return FraksiThresholds(
      batas0: double.parse(raw[0]),
      batas1: double.parse(raw[1]),
      batas2: double.parse(raw[2]),
      batas3: double.parse(raw[3]),
      batas4: double.parse(raw[4]),
      batas5: double.parse(raw[5]),
    );
  }

  Future<void> setFraksiThresholds(FraksiThresholds t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kFraksiThresholds, [
      t.batas0.toString(),
      t.batas1.toString(),
      t.batas2.toString(),
      t.batas3.toString(),
      t.batas4.toString(),
      t.batas5.toString(),
    ]);
  }

  // ---------------------------------------------------------------------
  // Sinkronisasi cloud (opsional) — lihat lib/services/sync_service.dart
  // ---------------------------------------------------------------------

  Future<String?> getCompanyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCompanyId);
  }

  Future<String?> getCompanyKode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCompanyKode);
  }

  Future<String?> getWorkerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kWorkerName);
  }

  /// Simpan hasil pendaftaran device ke sebuah company/kebun.
  Future<void> saveDeviceRegistration({
    required String companyId,
    required String kode,
    required String workerName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCompanyId, companyId);
    await prefs.setString(_kCompanyKode, kode);
    await prefs.setString(_kWorkerName, workerName);
  }

  Future<bool> isDeviceRegistered() async => (await getCompanyId()) != null;

  Future<bool> getAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoSync) ?? true;
  }

  Future<void> setAutoSyncEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSync, value);
  }

  Future<DateTime?> getLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastSyncAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSyncAt, time.toIso8601String());
  }
}
