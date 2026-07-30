import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/scan_result.dart';

/// Semua pembacaan/penulisan riwayat scan lewat SQLite lokal.
/// Tidak ada request jaringan sama sekali — 100% offline.
class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sawit_vision.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scan_results (
            id TEXT PRIMARY KEY,
            timestamp TEXT NOT NULL,
            imagePath TEXT NOT NULL,
            mode TEXT NOT NULL,
            jumlahJanjang INTEGER NOT NULL DEFAULT 0,
            estimasiBrondol INTEGER NOT NULL DEFAULT 0,
            ukuranJanjang TEXT NOT NULL DEFAULT 'sedang',
            persenBrondol REAL NOT NULL DEFAULT 0,
            fraksi TEXT NOT NULL DEFAULT 'f00',
            blok TEXT NOT NULL DEFAULT '',
            catatan TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_scan_timestamp ON scan_results (timestamp)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Menambahkan dukungan sinkronisasi opsional ke web dashboard.
          // Data lama dianggap belum tersinkron (default 0) — aman diulang.
          await db.execute(
              'ALTER TABLE scan_results ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
  }

  Future<void> insertScan(ScanResult scan) async {
    final db = await database;
    await db.insert(
      'scan_results',
      scan.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateScan(ScanResult scan) async {
    final db = await database;
    await db.update(
      'scan_results',
      scan.toMap(),
      where: 'id = ?',
      whereArgs: [scan.id],
    );
  }

  Future<void> deleteScan(String id) async {
    final db = await database;
    await db.delete('scan_results', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ScanResult>> getAllScans({String? blokFilter}) async {
    final db = await database;
    final maps = await db.query(
      'scan_results',
      where: blokFilter != null && blokFilter.isNotEmpty ? 'blok = ?' : null,
      whereArgs: blokFilter != null && blokFilter.isNotEmpty ? [blokFilter] : null,
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => ScanResult.fromMap(m)).toList();
  }

  /// Semua scan yang belum berhasil disinkronkan ke web dashboard.
  /// Dipakai oleh [SyncService] — kosong selamanya jika user tidak pernah
  /// mengaktifkan sinkronisasi, tanpa efek samping apapun ke fitur lain.
  Future<List<ScanResult>> getUnsyncedScans() async {
    final db = await database;
    final maps = await db.query(
      'scan_results',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => ScanResult.fromMap(m)).toList();
  }

  Future<void> markSynced(String id) async {
    final db = await database;
    await db.update(
      'scan_results',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countUnsynced() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COUNT(*) as c FROM scan_results WHERE synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<ScanResult>> getScansBetween(DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'scan_results',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => ScanResult.fromMap(m)).toList();
  }

  Future<Map<String, dynamic>> getTodaySummary() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final scans = await getScansBetween(start, end);

    final totalJanjang = scans.fold<int>(
        0, (sum, s) => sum + (s.mode == ScanMode.janjang ? s.jumlahJanjang : 0));
    final totalBrondolScans =
        scans.where((s) => s.mode == ScanMode.brondol).length;
    final idealCount = scans.where((s) => s.fraksi.ideal).length;

    return {
      'totalScan': scans.length,
      'totalJanjang': totalJanjang,
      'totalBrondolScans': totalBrondolScans,
      'idealCount': idealCount,
    };
  }
}
