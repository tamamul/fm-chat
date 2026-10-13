import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Pembatal {
  bool batal = false;
}

// Salinan file yang diunduh, disimpan permanen di memori internal aplikasi.
class Lokal {
  static Directory? _akar;
  static final Set<String> _ada = {};
  static final Map<String, String> _jalur = {};
  static final ValueNotifier<int> berubah = ValueNotifier(0);

  static Future<Directory> akar() async {
    final a = _akar;
    if (a != null) return a;
    final d = await getApplicationDocumentsDirectory();
    final r = Directory('${d.path}/berkas');
    if (!await r.exists()) await r.create(recursive: true);
    _akar = r;
    return r;
  }

  static String kunci(String urlPath) => urlPath.replaceAll('/', '_');

  static String aman(String nama) => nama.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static Future<Directory> dirUntuk(String urlPath) async {
    final r = await akar();
    final d = Directory('${r.path}/${kunci(urlPath)}');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static File? _isi(Directory d) {
    if (!d.existsSync()) return null;
    for (final e in d.listSync()) {
      if (e is File && !e.path.endsWith('.part') && e.lengthSync() > 0) return e;
    }
    return null;
  }

  // Baca daftar unduhan yang ada (dipanggil saat aplikasi dibuka).
  static Future<void> muat() async {
    try {
      final r = await akar();
      _ada.clear();
      _jalur.clear();
      for (final e in r.listSync()) {
        if (e is Directory) {
          final f = _isi(e);
          if (f != null) {
            final k = e.path.split('/').last;
            _ada.add(k);
            _jalur[k] = f.path;
          }
        }
      }
    } catch (_) {}
    berubah.value++;
  }

  static bool ada(String urlPath) => _ada.contains(kunci(urlPath));

  // Jalur file lokal tanpa menunggu (null kalau belum diunduh).
  static String? pathSync(String urlPath) => _jalur[kunci(urlPath)];

  static Future<String?> path(String urlPath) async {
    final r = await akar();
    return _isi(Directory('${r.path}/${kunci(urlPath)}'))?.path;
  }

  static void tandai(String urlPath, String path) {
    final k = kunci(urlPath);
    _ada.add(k);
    _jalur[k] = path;
    berubah.value++;
  }

  static Future<void> hapus(String urlPath) async {
    try {
      final r = await akar();
      final d = Directory('${r.path}/${kunci(urlPath)}');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    _ada.remove(kunci(urlPath));
    _jalur.remove(kunci(urlPath));
    berubah.value++;
  }

  static Future<void> hapusSemua() async {
    try {
      final r = await akar();
      for (final e in r.listSync()) {
        await e.delete(recursive: true);
      }
    } catch (_) {}
    _ada.clear();
    _jalur.clear();
    berubah.value++;
  }

  static Future<int> totalUkuran() async {
    var total = 0;
    try {
      final r = await akar();
      for (final e in r.listSync(recursive: true)) {
        if (e is File) total += e.lengthSync();
      }
    } catch (_) {}
    return total;
  }
}