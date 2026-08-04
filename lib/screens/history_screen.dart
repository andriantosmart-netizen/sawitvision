import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../utils/constants.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ScanResult> _scans = [];
  bool _loading = true;
  final _dateFormat = DateFormat('dd MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final scans = await DatabaseService.instance.getAllScans();
    setState(() {
      _scans = scans;
      _loading = false;
    });
  }

  Future<void> _export() async {
    if (_scans.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Belum ada data untuk diekspor.')));
      return;
    }
    await ExportService().exportAndShare(_scans);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Scan'),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share), onPressed: _export),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scans.isEmpty
              ? const Center(child: Text('Belum ada riwayat scan.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _scans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = _scans[i];
                      final isBrondol = s.mode == ScanMode.brondol;
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              Navigator.pushNamed(context, '/detail', arguments: s),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(s.imagePath),
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 56,
                                      height: 56,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_not_supported),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isBrondol
                                            ? '${s.brdFinalKg.toStringAsFixed(1)} kg (${s.estimasiBrondol} tumpukan)'
                                            : '${s.jumlahJanjang} janjang'
                                                '${s.janjangKosong > 0 ? ' (${s.janjangKosong} kosong)' : ''}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(_dateFormat.format(s.timestamp),
                                          style: const TextStyle(
                                              fontSize: 12, color: Colors.black54)),
                                      if (s.blok.isNotEmpty)
                                        Text('Blok: ${s.blok}',
                                            style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
