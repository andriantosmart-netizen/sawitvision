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

  /// Dipakai [BoundingBoxEditor] (lib/widgets/bounding_box_editor.dart) untuk
  /// membuat salinan dengan sebagian field diubah (geser/resize/reklasifikasi
  /// kotak) tanpa mengubah instance lama -- [DetectedObject] sengaja immutable.
  DetectedObject copyWith({
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
    double? confidence,
  }) {
    return DetectedObject(
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      confidence: confidence ?? this.confidence,
    );
  }

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

  final int jumlahJanjang; // hasil untuk mode janjang (dari jumlah kotak 'janjang')

  /// Untuk mode brondol: jumlah TUMPUKAN/kelompok brondol yang ditandai
  /// (dari jumlah kotak 'brondol') -- BUKAN lagi estimasi butir/fruitlet
  /// individual seperti versi lama. Dikalikan [brdKgPerTumpukan] untuk
  /// dapat [brdFinalKg], persis pola "Tumpukan x Kg" di koreksi.html (Web).
  final int estimasiBrondol;

  /// Jumlah kotak 'janjang_kosong' (tandan kosong tanpa buah) yang ditandai
  /// di foto ini -- bisa muncul di kedua mode, tapi paling relevan di mode
  /// Hitung Janjang.
  final int janjangKosong;

  /// Kalibrasi berat (kg) per satu tumpukan brondol yang dipakai saat scan
  /// ini disimpan (preset 3/5/7 atau custom, lihat SettingsScreen &
  /// ResultScreen). 0 untuk mode janjang / belum diisi.
  final double brdKgPerTumpukan;

  /// Hasil akhir: estimasiBrondol (jumlah tumpukan) x brdKgPerTumpukan,
  /// DISIMPAN (bukan dihitung ulang) supaya riwayat lama tidak berubah
  /// kalau kalibrasi default di Settings diubah belakangan.
  final double brdFinalKg;

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
    this.janjangKosong = 0,
    this.brdKgPerTumpukan = 0,
    this.brdFinalKg = 0,
    this.blok = '',
    this.catatan = '',
    this.latitude,
    this.longitude,
    this.synced = false,
  });

  ScanResult copyWith({
    int? jumlahJanjang,
    int? estimasiBrondol,
    int? janjangKosong,
    double? brdKgPerTumpukan,
    double? brdFinalKg,
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
      janjangKosong: janjangKosong ?? this.janjangKosong,
      brdKgPerTumpukan: brdKgPerTumpukan ?? this.brdKgPerTumpukan,
      brdFinalKg: brdFinalKg ?? this.brdFinalKg,
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
        'janjangKosong': janjangKosong,
        'brdKgPerTumpukan': brdKgPerTumpukan,
        'brdFinalKg': brdFinalKg,
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
        janjangKosong: map['janjangKosong'] as int? ?? 0,
        brdKgPerTumpukan: (map['brdKgPerTumpukan'] as num?)?.toDouble() ?? 0,
        brdFinalKg: (map['brdFinalKg'] as num?)?.toDouble() ?? 0,
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
      'janjang_kosong': janjangKosong,
      'brd_kg_per_tumpukan': brdKgPerTumpukan,
      'brd_final_kg': brdFinalKg,
      'blok': blok,
      'catatan': catatan,
      'latitude': latitude,
      'longitude': longitude,
      'photo_path': '$companyId/$id.jpg',
      'captured_at': timestamp.toIso8601String(),
    };
  }
}
