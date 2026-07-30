import 'fraksi.dart';

/// Mode pemindaian yang tersedia.
enum ScanMode { janjang, brondol }

extension ScanModeInfo on ScanMode {
  String get label =>
      this == ScanMode.janjang ? 'Hitung Janjang' : 'Taksasi Brondol';
}

/// Satu objek yang terdeteksi pada foto (janjang atau brondol individual).
class DetectedObject {
  final String label; // 'janjang' | 'brondol'
  final double x; // koordinat relatif (0-1) dari kiri
  final double y; // koordinat relatif (0-1) dari atas
  final double width; // lebar relatif (0-1)
  final double height; // tinggi relatif (0-1)
  final double confidence; // 0-1

  const DetectedObject({
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  Map<String, dynamic> toMap() => {
        'label': label,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'confidence': confidence,
      };

  factory DetectedObject.fromMap(Map<String, dynamic> map) => DetectedObject(
        label: map['label'] as String,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        width: (map['width'] as num).toDouble(),
        height: (map['height'] as num).toDouble(),
        confidence: (map['confidence'] as num).toDouble(),
      );
}

/// Satu record hasil pemindaian yang disimpan ke database lokal.
class ScanResult {
  final String id;
  final DateTime timestamp;
  final String imagePath;
  final ScanMode mode;

  final int jumlahJanjang; // hasil untuk mode janjang
  final int estimasiBrondol; // hasil untuk mode brondol
  final UkuranJanjang ukuranJanjang;
  final double persenBrondol;
  final Fraksi fraksi;

  final String blok; // nama/kode blok kebun
  final String catatan;
  final double? latitude;
  final double? longitude;

  /// Sudah berhasil disinkronkan ke web dashboard (Supabase) atau belum.
  /// Sinkronisasi bersifat opsional — nilai ini tetap `false` selamanya jika
  /// user tidak pernah mengaktifkan fitur sync, dan aplikasi tetap berjalan
  /// normal sepenuhnya offline.
  final bool synced;

  const ScanResult({
    required this.id,
    required this.timestamp,
    required this.imagePath,
    required this.mode,
    this.jumlahJanjang = 0,
    this.estimasiBrondol = 0,
    this.ukuranJanjang = UkuranJanjang.sedang,
    this.persenBrondol = 0,
    this.fraksi = Fraksi.f00,
    this.blok = '',
    this.catatan = '',
    this.latitude,
    this.longitude,
    this.synced = false,
  });

  ScanResult copyWith({
    int? jumlahJanjang,
    int? estimasiBrondol,
    UkuranJanjang? ukuranJanjang,
    double? persenBrondol,
    Fraksi? fraksi,
    String? blok,
    String? catatan,
    bool? synced,
  }) {
    return ScanResult(
      id: id,
      timestamp: timestamp,
      imagePath: imagePath,
      mode: mode,
      jumlahJanjang: jumlahJanjang ?? this.jumlahJanjang,
      estimasiBrondol: estimasiBrondol ?? this.estimasiBrondol,
      ukuranJanjang: ukuranJanjang ?? this.ukuranJanjang,
      persenBrondol: persenBrondol ?? this.persenBrondol,
      fraksi: fraksi ?? this.fraksi,
      blok: blok ?? this.blok,
      catatan: catatan ?? this.catatan,
      latitude: latitude,
      longitude: longitude,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'imagePath': imagePath,
        'mode': mode.name,
        'jumlahJanjang': jumlahJanjang,
        'estimasiBrondol': estimasiBrondol,
        'ukuranJanjang': ukuranJanjang.name,
        'persenBrondol': persenBrondol,
        'fraksi': fraksi.name,
        'blok': blok,
        'catatan': catatan,
        'latitude': latitude,
        'longitude': longitude,
        'synced': synced ? 1 : 0,
      };

  factory ScanResult.fromMap(Map<String, dynamic> map) => ScanResult(
        id: map['id'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        imagePath: map['imagePath'] as String,
        mode: ScanMode.values.byName(map['mode'] as String),
        jumlahJanjang: map['jumlahJanjang'] as int? ?? 0,
        estimasiBrondol: map['estimasiBrondol'] as int? ?? 0,
        ukuranJanjang:
            UkuranJanjang.values.byName(map['ukuranJanjang'] as String? ?? 'sedang'),
        persenBrondol: (map['persenBrondol'] as num?)?.toDouble() ?? 0,
        fraksi: Fraksi.values.byName(map['fraksi'] as String? ?? 'f00'),
        blok: map['blok'] as String? ?? '',
        catatan: map['catatan'] as String? ?? '',
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        synced: ((map['synced'] as int?) ?? 0) == 1,
      );

  /// Payload untuk tabel `scan_results` di Supabase (kolom snake_case,
  /// berbeda dari `toMap()` yang dipakai untuk SQLite lokal).
  Map<String, dynamic> toSupabasePayload({
    required String companyId,
    required String deviceId,
  }) {
    return {
      'id': id,
      'company_id': companyId,
      'device_id': deviceId,
      'mode': mode.name,
      'jumlah_janjang': jumlahJanjang,
      'estimasi_brondol': estimasiBrondol,
      'ukuran_janjang': ukuranJanjang.name,
      'persen_brondol': persenBrondol,
      'fraksi': fraksi.name,
      'blok': blok,
      'catatan': catatan,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': '$companyId/$id.jpg',
      'captured_at': timestamp.toIso8601String(),
    };
  }
}
