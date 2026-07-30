import 'package:flutter/material.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sinkronisasi ke web dashboard bersifat opsional. Selama
  // lib/config/supabase_config.dart belum diisi kredensial Supabase asli,
  // baris di bawah ini otomatis dilewati dan aplikasi berjalan 100% offline
  // seperti biasa — lihat docs/ARSITEKTUR.md & sawit_vision_web/docs/.
  if (SupabaseConfig.isConfigured) {
    await SupabaseService.instance.init();
    SyncService.instance.startAutoSyncListener();
  }

  runApp(const SawitVisionApp());
}
