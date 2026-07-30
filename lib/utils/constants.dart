import 'package:flutter/material.dart';
import '../models/fraksi.dart';

class AppColors {
  static const primary = Color(0xFF2E7D32); // hijau sawit
  static const accent = Color(0xFFE65100); // oranye buah matang
  static const background = Color(0xFFF5F7F5);
  static const cardBorder = Color(0xFFE0E0E0);

  static Color forFraksi(Fraksi f) {
    if (f.ideal) return const Color(0xFF2E7D32); // hijau — ideal
    if (!f.diterima) return const Color(0xFFC62828); // merah — tolak
    return const Color(0xFFF9A825); // kuning — kurang/lewat matang
  }
}

class AppSpacing {
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
}
