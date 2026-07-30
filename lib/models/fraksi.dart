/// Standar Fraksi Kematangan Tandan Buah Segar (TBS) kelapa sawit.
///
/// Ambang batas persen brondol di bawah ini adalah acuan umum industri.
/// Nilainya dibuat konfigurasi (lihat [FraksiThresholds]) karena setiap
/// PKS/kebun bisa punya SOP sendiri.
enum Fraksi {
  f00, // sangat mentah
  f0, // mentah
  f1, // kurang matang
  f2, // matang I
  f3, // matang II
  f4, // lewat matang I
  f5, // lewat matang II / janjang kosong
}

extension FraksiInfo on Fraksi {
  String get label {
    switch (this) {
      case Fraksi.f00:
        return 'Fraksi 00';
      case Fraksi.f0:
        return 'Fraksi 0';
      case Fraksi.f1:
        return 'Fraksi 1';
      case Fraksi.f2:
        return 'Fraksi 2';
      case Fraksi.f3:
        return 'Fraksi 3';
      case Fraksi.f4:
        return 'Fraksi 4';
      case Fraksi.f5:
        return 'Fraksi 5';
    }
  }

  String get deskripsi {
    switch (this) {
      case Fraksi.f00:
        return 'Sangat mentah — seluruh buah masih hitam';
      case Fraksi.f0:
        return 'Mentah — buah luar mulai berubah warna';
      case Fraksi.f1:
        return 'Kurang matang';
      case Fraksi.f2:
        return 'Matang I — kondisi ideal panen';
      case Fraksi.f3:
        return 'Matang II — kondisi ideal panen';
      case Fraksi.f4:
        return 'Lewat matang I';
      case Fraksi.f5:
        return 'Lewat matang II — janjang kosong, buah dalam ikut lepas';
    }
  }

  /// Apakah fraksi ini termasuk kategori yang diterima PKS.
  bool get diterima => this != Fraksi.f00 && this != Fraksi.f5;

  /// Apakah fraksi ini kondisi ideal (rendemen minyak optimal).
  bool get ideal => this == Fraksi.f2 || this == Fraksi.f3;
}

/// Ambang batas persentase brondol (dapat dikalibrasi lewat Settings).
class FraksiThresholds {
  final double batas0; // >= ini masuk Fraksi 0
  final double batas1;
  final double batas2;
  final double batas3;
  final double batas4;
  final double batas5;

  const FraksiThresholds({
    this.batas0 = 1.0,
    this.batas1 = 12.5,
    this.batas2 = 25.0,
    this.batas3 = 50.0,
    this.batas4 = 75.0,
    this.batas5 = 100.0,
  });

  factory FraksiThresholds.fromMap(Map<String, dynamic> map) {
    return FraksiThresholds(
      batas0: (map['batas0'] as num?)?.toDouble() ?? 1.0,
      batas1: (map['batas1'] as num?)?.toDouble() ?? 12.5,
      batas2: (map['batas2'] as num?)?.toDouble() ?? 25.0,
      batas3: (map['batas3'] as num?)?.toDouble() ?? 50.0,
      batas4: (map['batas4'] as num?)?.toDouble() ?? 75.0,
      batas5: (map['batas5'] as num?)?.toDouble() ?? 100.0,
    );
  }

  Map<String, dynamic> toMap() => {
        'batas0': batas0,
        'batas1': batas1,
        'batas2': batas2,
        'batas3': batas3,
        'batas4': batas4,
        'batas5': batas5,
      };

  /// Petakan persentase brondol (0-100+) ke [Fraksi] sesuai ambang batas ini.
  Fraksi hitungFraksi(double persenBrondol) {
    if (persenBrondol < batas0) return Fraksi.f00;
    if (persenBrondol < batas1) return Fraksi.f0;
    if (persenBrondol < batas2) return Fraksi.f1;
    if (persenBrondol < batas3) return Fraksi.f2;
    if (persenBrondol < batas4) return Fraksi.f3;
    if (persenBrondol < batas5) return Fraksi.f4;
    return Fraksi.f5;
  }
}

/// Kategori ukuran janjang, dipakai sebagai referensi estimasi total
/// jumlah brondol per tandan (nilai default berbasis referensi agronomi,
/// bisa dikalibrasi manual di Settings begitu ada data lapangan sendiri).
enum UkuranJanjang { kecil, sedang, besar }

extension UkuranJanjangInfo on UkuranJanjang {
  String get label {
    switch (this) {
      case UkuranJanjang.kecil:
        return 'Kecil (< 10 kg)';
      case UkuranJanjang.sedang:
        return 'Sedang (10 - 20 kg)';
      case UkuranJanjang.besar:
        return 'Besar (> 20 kg)';
    }
  }

  /// Estimasi default jumlah total brondol/fruitlet per tandan.
  int get defaultTotalBrondol {
    switch (this) {
      case UkuranJanjang.kecil:
        return 1000;
      case UkuranJanjang.sedang:
        return 1500;
      case UkuranJanjang.besar:
        return 2200;
    }
  }
}
