import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';

class AuthState {
  final bool isLoggedIn;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.isLoggedIn = false,
    this.token,
    this.user,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? token,
    Map<String, dynamic>? user,
    String? error,
    bool? isLoading,
  }) =>
      AuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        token: token ?? this.token,
        user: user ?? this.user,
        error: error,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;

  AuthNotifier({Dio? dio, AuthState? initialState})
      : _dio = dio ?? buildDio(),
        super(initialState ?? const AuthState());

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        Endpoints.login,
        data: {'email': email, 'password': password},
      );
      final token = response.data['token'] as String;
      final user = response.data['user'] as Map<String, dynamic>;
      await saveToken(token);
      state = state.copyWith(
        isLoggedIn: true,
        token: token,
        user: user,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e),
      );
    }
  }

  Future<void> logout() async {
    await clearToken();
    state = const AuthState();
  }

  String _extractError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) return data['error'] as String;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return 'Could not reach the server. Check the server address in Settings.';
      }
      return 'Login failed (${e.response?.statusCode ?? 'no response'}).';
    }
    return 'Login failed. Check your connection and try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);

/// Reads any saved token and decodes its role/email so the very first
/// GoRouter redirect at app startup already knows the user is logged in --
/// must be awaited in main() before runApp, then passed in via
/// authProvider.overrideWith. Restoring the token asynchronously *after*
/// runApp (the previous approach) loses the race: GoRouter's first redirect
/// check always ran before the restore finished, so every restart bounced
/// back to the login screen despite a perfectly valid saved session.
Future<AuthState> loadInitialAuthState() async {
  final token = await readToken();
  if (token == null) return const AuthState();
  final payload = decodeJwtPayload(token);
  if (payload == null) {
    await clearToken();
    return const AuthState();
  }
  return AuthState(
    isLoggedIn: true,
    token: token,
    user: {
      'id': payload['user_id'] as String? ?? '',
      'email': payload['email'] as String? ?? '',
      'role': payload['role'] as String? ?? '',
      'organization_id': payload['organization_id'] as String? ?? '',
    },
  );
}

final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authProvider).isLoggedIn,
);

final currentUserProvider = Provider<Map<String, dynamic>?>(
  (ref) => ref.watch(authProvider).user,
);
