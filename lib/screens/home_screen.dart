import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../models/scan_result.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';
import '../widgets/stat_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _summary;
  int _unsyncedCount = 0;
  bool _syncEnabled = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DatabaseService.instance.getTodaySummary();
    final unsynced = await DatabaseService.instance.countUnsynced();
    final registered = await SettingsService().isDeviceRegistered();
    if (mounted) {
      setState(() {
        _summary = s;
        _unsyncedCount = unsynced;
        _syncEnabled = SupabaseConfig.isConfigured && registered;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await SyncService.instance.syncPending();
    await _load();
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SawitVision'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const Text('Ringkasan Hari Ini',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            if (s == null)
              const Center(child: CircularProgressIndicator())
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 1.5,
                children: [
                  StatCard(
                    label: 'Total Scan',
                    value: '${s['totalScan']}',
                    icon: Icons.qr_code_scanner,
                  ),
                  StatCard(
                    label: 'Total Janjang',
                    value: '${s['totalJanjang']}',
                    icon: Icons.eco,
                    color: AppColors.primary,
                  ),
                  StatCard(
                    label: 'Taksasi Brondol',
                    value: '${s['totalBrondolScans']}',
                    icon: Icons.grain,
                    color: AppColors.accent,
                  ),
                  StatCard(
                    label: 'Kondisi Ideal',
                    value: '${s['idealCount']}',
                    icon: Icons.verified,
                    color: Colors.green.shade700,
                  ),
                ],
              ),
            if (_syncEnabled && _unsyncedCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 20, color: Colors.black54),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('$_unsyncedCount data belum tersinkron ke web dashboard.',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: _syncing ? null : _syncNow,
                      child: _syncing
                          ? const SizedBox(
                              height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sync'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Text('Mulai Pindai',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            _ModeButton(
              icon: Icons.eco,
              title: 'Hitung Janjang',
              subtitle: 'Hitung jumlah tandan buah segar (TBS) di TPH',
              color: AppColors.primary,
              onTap: () => Navigator.pushNamed(context, '/scan',
                  arguments: ScanMode.janjang),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ModeButton(
              icon: Icons.grain,
              title: 'Taksasi Brondol',
              subtitle: 'Estimasi jumlah brondol & fraksi kematangan',
              color: AppColors.accent,
              onTap: () => Navigator.pushNamed(context, '/scan',
                  arguments: ScanMode.brondol),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Riwayat'),
                    onPressed: () => Navigator.pushNamed(context, '/history'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Statistik'),
                    onPressed: () => Navigator.pushNamed(context, '/stats'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
