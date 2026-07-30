import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_result.dart';
import '../models/fraksi.dart';

/// Ekspor riwayat scan ke CSV, lalu buka share sheet Android (kirim via
/// WhatsApp/Email/simpan ke Drive, dsb.) — proses ekspor sendiri tetap
/// lokal, hanya berbagi filenya yang butuh aplikasi lain/koneksi.
class ExportService {
  Future<File> exportToCsv(List<ScanResult> scans) async {
    final rows = <List<dynamic>>[
      [
        'Tanggal',
        'Mode',
        'Blok',
        'Jumlah Janjang',
        'Estimasi Brondol',
        'Ukuran Janjang',
        'Persen Brondol',
        'Fraksi',
        'Catatan',
      ],
      ...scans.map((s) => [
            s.timestamp.toIso8601String(),
            s.mode.label,
            s.blok,
            s.jumlahJanjang,
            s.estimasiBrondol,
            s.ukuranJanjang.label,
            s.persenBrondol.toStringAsFixed(1),
            s.fraksi.label,
            s.catatan,
          ]),
    ];

    final csvData = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'sawit_vision_export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvData);
    return file;
  }

  Future<void> exportAndShare(List<ScanResult> scans) async {
    final file = await exportToCsv(scans);
    await Share.shareXFiles([XFile(file.path)],
        text: 'Riwayat scan SawitVision');
  }
}
