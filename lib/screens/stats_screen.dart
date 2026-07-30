import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/scan_result.dart';
import '../models/fraksi.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  List<MapEntry<DateTime, int>> _janjangPerHari = [];
  Map<Fraksi, int> _fraksiCount = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final scans = await DatabaseService.instance.getScansBetween(start, now.add(const Duration(days: 1)));

    final perHari = <DateTime, int>{};
    for (int i = 0; i < 7; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      perHari[d] = 0;
    }
    final fraksiCount = <Fraksi, int>{};

    for (final s in scans) {
      final d = DateTime(s.timestamp.year, s.timestamp.month, s.timestamp.day);
      if (perHari.containsKey(d) && s.mode == ScanMode.janjang) {
        perHari[d] = (perHari[d] ?? 0) + s.jumlahJanjang;
      }
      if (s.mode == ScanMode.brondol) {
        fraksiCount[s.fraksi] = (fraksiCount[s.fraksi] ?? 0) + 1;
      }
    }

    setState(() {
      _janjangPerHari = perHari.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      _fraksiCount = fraksiCount;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Text('Jumlah Janjang — 7 Hari Terakhir',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 220,
                  child: _janjangPerHari.every((e) => e.value == 0)
                      ? const Center(child: Text('Belum ada data.'))
                      : BarChart(
                          BarChartData(
                            barGroups: [
                              for (int i = 0; i < _janjangPerHari.length; i++)
                                BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: _janjangPerHari[i].value.toDouble(),
                                    color: AppColors.primary,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(4),
                                  )
                                ]),
                            ],
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    if (i < 0 || i >= _janjangPerHari.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        DateFormat('dd/MM').format(_janjangPerHari[i].key),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Distribusi Fraksi Kematangan',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 220,
                  child: _fraksiCount.isEmpty
                      ? const Center(child: Text('Belum ada data taksasi brondol.'))
                      : PieChart(
                          PieChartData(
                            sections: _fraksiCount.entries
                                .map((e) => PieChartSectionData(
                                      value: e.value.toDouble(),
                                      title: '${e.key.label}\n(${e.value})',
                                      titleStyle: const TextStyle(
                                          fontSize: 10, color: Colors.white),
                                      color: AppColors.forFraksi(e.key),
                                      radius: 70,
                                    ))
                                .toList(),
                            sectionsSpace: 2,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
