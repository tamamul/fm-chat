import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'https://berkas.marsa9.com';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Api {
  static const _storage = FlutterSecureStorage();
  static String? _token;

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
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final r = await http
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
      return Map<String, dynamic>.from(data['user']);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Tidak bisa terhubung ke server.');
    }
  }

  static Future<Map<String, dynamic>?> me() async {
    if (_token == null) return null;
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/api/me'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 401) {
        await _clear();
        return null;
      }
      if (r.statusCode != 200) throw ApiError('Server bermasalah (${r.statusCode}).');
      return Map<String, dynamic>.from(jsonDecode(r.body));
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Tidak bisa terhubung ke server.');
    }
  }

  static Future<void> logout() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/api/logout'), headers: _headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    await _clear();
  }

  static Future<dynamic> getJson(String path) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/api$path'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 401) {
        await _clear();
        throw ApiError('Sesi berakhir, silakan masuk lagi.');
      }
      if (r.statusCode != 200) throw ApiError('Server bermasalah (${r.statusCode}).');
      return jsonDecode(r.body);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Tidak bisa terhubung ke server.');
    }
  }
}
