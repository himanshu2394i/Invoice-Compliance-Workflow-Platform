import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Singleton that holds the backend server base URL, persisted across app
/// restarts via encrypted secure storage. Change it from the Settings screen.
class ServerConfig {
  static const _key = 'server_base_url';
  static const defaultUrl = 'https://203.0.113.10';

  static final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _baseUrl = defaultUrl;

  /// Current base URL. Always valid after [load] has been awaited at startup.
  static String get baseUrl => _baseUrl;

  /// Load persisted URL from storage. Call once before runApp.
  static Future<void> load() async {
    final saved = await _storage.read(key: _key);
    if (saved == null || saved.contains('sslip.io') || saved.contains('10.0.2.2')) {
      _baseUrl = defaultUrl;
      await _storage.write(key: _key, value: defaultUrl);
    } else {
      _baseUrl = saved;
    }
  }

  /// Persist a new URL and update the in-memory value immediately.
  static Future<void> save(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/$'), '');
    _baseUrl = clean.isEmpty ? defaultUrl : clean;
    await _storage.write(key: _key, value: _baseUrl);
  }

  static Future<void> reset() async {
    _baseUrl = defaultUrl;
    await _storage.delete(key: _key);
  }
}
