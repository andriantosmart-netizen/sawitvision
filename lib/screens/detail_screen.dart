import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';
import '../widgets/grade_badge.dart';

class DetailScreen extends StatelessWidget {
  final ScanResult scan;
  const DetailScreen({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final isBrondol = scan.mode == ScanMode.brondol;
    final dateFormat = DateFormat('dd MMMM yyyy, HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Hapus data ini?'),
                  content: const Text('Data yang dihapus tidak bisa dikembalikan.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Hapus')),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseService.instance.deleteScan(scan.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(scan.imagePath), fit: BoxFit.cover),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(dateFormat.format(scan.timestamp),
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isBrondol
                ? 'Estimasi Brondol: ${scan.estimasiBrondol}'
                : 'Jumlah Janjang: ${scan.jumlahJanjang}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (isBrondol) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                GradeBadge(fraksi: scan.fraksi),
                const SizedBox(width: AppSpacing.sm),
                Text('${scan.persenBrondol.toStringAsFixed(1)}% brondol'),
              ],
            ),
            const SizedBox(height: 4),
            Text('Ukuran janjang: ${scan.ukuranJanjang.label}',
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
          const SizedBox(height: AppSpacing.md),
          if (scan.blok.isNotEmpty) ...[
            const Text('Blok / Lokasi', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(scan.blok),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (scan.catatan.isNotEmpty) ...[
            const Text('Catatan', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(scan.catatan),
          ],
        ],
      ),
    );
  }
}
