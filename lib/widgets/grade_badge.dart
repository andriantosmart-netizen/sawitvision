import 'package:flutter/material.dart';
import '../models/fraksi.dart';
import '../utils/constants.dart';

/// Badge kecil menampilkan Fraksi + warna status (hijau=ideal,
/// kuning=kurang/lewat matang, merah=tolak).
class GradeBadge extends StatelessWidget {
  final Fraksi fraksi;
  final bool compact;

  const GradeBadge({super.key, required this.fraksi, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forFraksi(fraksi);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        fraksi.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 12 : 14,
        ),
      ),
    );
  }
}
