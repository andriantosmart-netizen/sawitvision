import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/scan_result.dart';
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
  List<MapEntry<DateTime, double>> _brondolKgPerHari = [];

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

    final janjangPerHari = <DateTime, int>{};
    final brondolKgPerHari = <DateTime, double>{};
    for (int i = 0; i < 7; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      janjangPerHari[d] = 0;
      brondolKgPerHari[d] = 0;
    }

    for (final s in scans) {
      final d = DateTime(s.timestamp.year, s.timestamp.month, s.timestamp.day);
      if (!janjangPerHari.containsKey(d)) continue;
      if (s.mode == ScanMode.janjang) {
        janjangPerHari[d] = (janjangPerHari[d] ?? 0) + s.jumlahJanjang;
      } else {
        brondolKgPerHari[d] = (brondolKgPerHari[d] ?? 0) + s.brdFinalKg;
      }
    }

    setState(() {
      _janjangPerHari = janjangPerHari.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      _brondolKgPerHari = brondolKgPerHari.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
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
                const Text('Kg Brondol — 7 Hari Terakhir',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 220,
                  child: _brondolKgPerHari.every((e) => e.value == 0)
                      ? const Center(child: Text('Belum ada data taksasi brondol.'))
                      : BarChart(
                          BarChartData(
                            barGroups: [
                              for (int i = 0; i < _brondolKgPerHari.length; i++)
                                BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: _brondolKgPerHari[i].value,
                                    color: AppColors.accent,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(4),
                                  )
                                ]),
                            ],
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    if (i < 0 || i >= _brondolKgPerHari.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        DateFormat('dd/MM').format(_brondolKgPerHari[i].key),
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
              ],
            ),
    );
  }
}
