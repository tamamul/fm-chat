import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api.dart';

class Push {
  static bool _siap = false;
  static String? _token;

  // Dipanggil saat notifikasi diketuk; diisi oleh layar beranda.
  static void Function(Map<String, dynamic> data)? onBuka;

  static void _buka(RemoteMessage m) => onBuka?.call(Map<String, dynamic>.from(m.data));

  // Siapkan Firebase (sekali) lalu daftarkan token HP ini ke server (tiap login/buka).
  static Future<void> mulai() async {
    try {
      if (!_siap) {
        await Firebase.initializeApp();
        final fm = FirebaseMessaging.instance;
        fm.onTokenRefresh.listen((t) {
          _token = t;
          Api.daftarToken(t);
        });
        FirebaseMessaging.onMessageOpenedApp.listen(_buka);
        final awal = await fm.getInitialMessage();
        if (awal != null) _buka(awal);
        _siap = true;
      }
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      _token = await fm.getToken();
      if (_token != null) await Api.daftarToken(_token!);
    } catch (_) {}
  }

  // Dipanggil sebelum keluar akun supaya notifikasi akun ini berhenti di HP ini.
  static Future<void> lepas() async {
    if (_token != null) await Api.hapusToken(_token!);
  }
}