import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const baseUrl = 'https://berkas.marsa9.com';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Api {
  static const _storage = FlutterSecureStorage();
  static final http.Client _client = http.Client();
  static String? _token;

  static bool get punyaToken => _token != null;

  static Future<void> loadToken() async {
    _token = await _storage.read(key: 'token');
  }

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<void> _clear() async {
    _token = null;
    await _storage.delete(key: 'token');
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith('cache_')).toList()) {
      await p.remove(k);
    }
  }

  static Future<dynamic> readCache(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('cache_$key');
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeCache(String key, dynamic value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('cache_$key', jsonEncode(value));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final r = await _client
          .post(Uri.parse('$baseUrl/api/login'),
              headers: _headers,
              body: jsonEncode({'email': email, 'password': password, 'device_name': 'android'}))
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(r.body);
      if (r.statusCode != 200) {
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          throw ApiError((errors.values.first as List).first.toString());
        }
        throw ApiError(r.statusCode == 429 ? 'Terlalu banyak percobaan, coba lagi sebentar.' : 'Gagal masuk.');
      }
      _token = data['token'];
      await _storage.write(key: 'token', value: _token);
      final user = Map<String, dynamic>.from(data['user']);
      await writeCache('user', user);
      return user;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Tidak bisa terhubung ke server.');
    }
  }

  static Future<Map<String, dynamic>?> me() async {
    if (_token == null) return null;
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/api/me'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 401) {
        await _clear();
        return null;
      }
      if (r.statusCode != 200) throw ApiError('Server bermasalah (${r.statusCode}).');
      final user = Map<String, dynamic>.from(jsonDecode(r.body));
      await writeCache('user', user);
      return user;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Tidak bisa terhubung ke server.');
    }
  }

  static Future<dynamic> _decode(http.Response r) async {
    if (r.statusCode == 401) {
      await _clear();
      throw ApiError('Sesi berakhir, silakan masuk lagi.');
    }
    if (r.statusCode == 422) {
      try {
        final d = jsonDecode(r.body);
        final e = d['errors'];
        if (e is Map && e.isNotEmpty) {
          throw ApiError((e.values.first as List).first.toString());
        }
      } on ApiError {
        rethrow;
      } catch (_) {}
      throw ApiError('Data tidak valid.');
    }
    if (r.statusCode == 404) throw ApiError('Data tidak ditemukan.');
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiError('Server bermasalah (${r.statusCode}).');
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  static Future<dynamic> _req(Future<http.Response> Function() kirim) async {
    try {
      final r = await kirim().timeout(const Duration(seconds: 20));
      return await _decode(r);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Tidak bisa terhubung ke server.');
    }
  }

  static Future<dynamic> getJson(String path) =>
      _req(() => _client.get(Uri.parse('$baseUrl/api$path'), headers: _headers));

  static Future<dynamic> postJson(String path, Map<String, dynamic> body) => _req(() =>
      _client.post(Uri.parse('$baseUrl/api$path'), headers: _headers, body: jsonEncode(body)));

  static Future<dynamic> deleteJson(String path) =>
      _req(() => _client.delete(Uri.parse('$baseUrl/api$path'), headers: _headers));

  static Future<void> logout() async {
    try {
      await _client
          .post(Uri.parse('$baseUrl/api/logout'), headers: _headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    await _clear();
  }
}