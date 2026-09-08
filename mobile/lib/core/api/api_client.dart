import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _tokenKey = 'auth_token';

final _secureStorage = const FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

Dio buildDio() {
  final dio = Dio();
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  };
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _secureStorage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ),
  );
  return dio;
}

Future<void> saveToken(String token) =>
    _secureStorage.write(key: _tokenKey, value: token);

Future<void> clearToken() => _secureStorage.delete(key: _tokenKey);

Future<String?> readToken() => _secureStorage.read(key: _tokenKey);

/// Decodes a JWT's payload without verifying the signature -- fine for
/// reading our own previously-issued token to restore UI state (role, email)
/// at startup; every actual API call is still verified server-side regardless.
/// Returns null if the token is missing, malformed, or expired.
Map<String, dynamic>? decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final normalized = base64Url.normalize(parts[1]);
    final payload = json.decode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
    final exp = payload['exp'] as int?;
    if (exp != null && DateTime.now().millisecondsSinceEpoch >= exp * 1000) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}
