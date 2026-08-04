import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/result_screen.dart';
import 'screens/history_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'models/scan_result.dart';
import 'utils/constants.dart';

class SawitVisionApp extends StatelessWidget {
  const SawitVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SawitVision',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => const HomeScreen(),
        '/history': (context) => const HistoryScreen(),
        '/stats': (context) => const StatsScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/scan') {
          final mode = settings.arguments as ScanMode? ?? ScanMode.janjang;
          return MaterialPageRoute(builder: (_) => ScanScreen(mode: mode));
        }
        if (settings.name == '/result') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ResultScreen(
              imagePath: args['imagePath'] as String,
              mode: args['mode'] as ScanMode,
              initialBoxes: args['initialBoxes'] as List<DetectedObject>?,
            ),
          );
        }
        if (settings.name == '/detail') {
          final scan = settings.arguments as ScanResult;
          return MaterialPageRoute(builder: (_) => DetailScreen(scan: scan));
        }
        return null;
      },
    );
  }
}
