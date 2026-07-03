import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invoice_capture/core/config/server_config.dart';
import 'package:invoice_capture/features/auth/auth_provider.dart';
import 'package:invoice_capture/features/settings/settings_screen.dart';

Widget _settingsApp(AuthState authState) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
        (_) => AuthNotifier(initialState: authState),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('Home')),
          ),
        ],
      ),
    ),
  );
}

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
    // This only proves the in-memory value updates correctly; it would pass
    // identically even if the secure-storage write below were a no-op, since
    // save() assigns to the in-memory field before awaiting the storage
    // write. See the 'load() reads back what was actually written to secure
    // storage' test below for a real round-trip proof.
    await ServerConfig.save('http://192.168.1.42:8000/');
    expect(ServerConfig.baseUrl, 'http://192.168.1.42:8000');
  });

  test('reset restores the default emulator URL', () async {
    await ServerConfig.save('http://192.168.1.42:8000');
    await ServerConfig.reset();
    expect(ServerConfig.baseUrl, ServerConfig.defaultUrl);
  });

  test(
      'load() reads back what was actually written to secure storage, '
      'not whatever is cached in memory', () async {
    // Persist a value. This sets the in-memory field AND writes to the
    // storage stub's backing map.
    await ServerConfig.save('http://10.10.10.10:9000');

    // Reset the in-memory field to the default. reset() also clears the
    // storage stub's key, so to prove load() round-trips through storage
    // (rather than just trusting/keeping whatever is in memory) we put a
    // known value directly into the stub's backing map -- bypassing
    // ServerConfig entirely -- after reset() wipes both.
    await ServerConfig.reset();
    expect(ServerConfig.baseUrl, ServerConfig.defaultUrl);
    secureStorageData['server_base_url'] = 'http://172.16.5.5:7000';

    // ServerConfig._baseUrl is still the default at this point; nothing
    // ServerConfig-side has touched the new value. If load() merely kept
    // (or recomputed from) in-memory state, baseUrl would stay at the
    // default. Only a genuine read from the storage stub returns the
    // value that was injected directly into the backing map.
    await ServerConfig.load();
    expect(ServerConfig.baseUrl, 'http://172.16.5.5:7000');
  });

  testWidgets('logged-in users see the change password action', (tester) async {
    await tester.pumpWidget(_settingsApp(const AuthState(
      isLoggedIn: true,
      user: {'role': 'WORKER', 'email': 'worker@example.com'},
    )));

    expect(find.text('Change Password'), findsOneWidget);
  });

  testWidgets('admin users see the staff password reset action',
      (tester) async {
    await tester.pumpWidget(_settingsApp(const AuthState(
      isLoggedIn: true,
      user: {'role': 'ADMIN', 'email': 'admin@example.com'},
    )));

    expect(find.text('Reset Staff Password'), findsOneWidget);
  });
}
