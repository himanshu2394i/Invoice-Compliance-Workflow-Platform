import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:invoice_capture/core/config/server_config.dart';
import 'package:invoice_capture/features/auth/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AuthNotifier's constructor calls readToken() -> FlutterSecureStorage,
  // which under plain `flutter test` has no platform implementation and
  // throws MissingPluginException (TestWidgetsFlutterBinding.ensureInitialized()
  // alone does NOT register a fake for this channel). Stub the underlying
  // MethodChannel directly with an in-memory map so reads/writes behave like
  // real secure storage without touching a real platform.
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

  // http_mock_adapter's default FullHttpRequestMatcher compares the route
  // string against RequestOptions.path, which Dio sets to the *full* URL
  // when given an absolute URL (as Endpoints.login produces). So the mock
  // route must be the full URL, not a bare path.
  final loginUrl = '${ServerConfig.baseUrl}/api/v1/auth/login';

  setUp(() {
    // Each test should start with a clean slate: AuthNotifier's constructor
    // restores any previously saved token, which would otherwise leak
    // isLoggedIn state from the previous test's in-memory secure storage.
    secureStorageData.clear();
  });

  test('login success stores token and user, sets isLoggedIn', () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      loginUrl,
      (server) => server.reply(200, {
        'token': 'fake-jwt-token',
        'user': {'email': 'admin+abc@demo.local', 'role': 'ADMIN'},
      }),
      data: {'email': 'admin+abc@demo.local', 'password': 'ChangeMe123!'},
    );

    final notifier = AuthNotifier(dio: dio);
    await notifier.login('admin+abc@demo.local', 'ChangeMe123!');

    expect(notifier.state.isLoggedIn, true);
    expect(notifier.state.token, 'fake-jwt-token');
    expect(notifier.state.user?['role'], 'ADMIN');
    expect(notifier.state.error, null);
  });

  test('login failure (401) surfaces an error and does not set isLoggedIn',
      () async {
    final dio = Dio();
    final adapter = DioAdapter(dio: dio);
    adapter.onPost(
      loginUrl,
      (server) => server.reply(401, {'error': 'Invalid email or password'}),
      data: {'email': 'admin+abc@demo.local', 'password': 'wrong'},
    );

    final notifier = AuthNotifier(dio: dio);
    await notifier.login('admin+abc@demo.local', 'wrong');

    expect(notifier.state.isLoggedIn, false);
    expect(notifier.state.error, isNotNull);
  });
}
