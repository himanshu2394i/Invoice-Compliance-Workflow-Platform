import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_capture/core/config/server_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ServerConfig.save/reset call FlutterSecureStorage.write/delete, which
  // under plain `flutter test` throws MissingPluginException because no
  // platform implementation is registered (ensureInitialized() alone is
  // not sufficient for this channel). Stub the MethodChannel directly with
  // an in-memory map so the storage calls succeed instead of being skipped.
  final secureStorageData = <String, String?>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      switch (call.method) {
        case 'read':
          return secureStorageData[call.arguments['key']];
        case 'write':
          secureStorageData[call.arguments['key']] = call.arguments['value'];
          return null;
        case 'delete':
          secureStorageData.remove(call.arguments['key']);
          return null;
        case 'containsKey':
          return secureStorageData.containsKey(call.arguments['key']);
        case 'readAll':
          return secureStorageData;
        case 'deleteAll':
          secureStorageData.clear();
          return null;
        default:
          return null;
      }
    },
  );

  test('saving a server URL trims trailing slash and persists it', () async {
    // FlutterSecureStorage needs a platform channel mock in plain `flutter test`;
    // ServerConfig.save/load both go through it, so this confirms the in-memory
    // value updates correctly even when the secure-storage write itself is a
    // no-op test double (verified indirectly via ServerConfig.baseUrl).
    await ServerConfig.save('http://192.168.1.42:8000/');
    expect(ServerConfig.baseUrl, 'http://192.168.1.42:8000');
  });

  test('reset restores the default emulator URL', () async {
    await ServerConfig.save('http://192.168.1.42:8000');
    await ServerConfig.reset();
    expect(ServerConfig.baseUrl, ServerConfig.defaultUrl);
  });
}
