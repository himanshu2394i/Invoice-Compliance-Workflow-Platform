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

  AuthNotifier({Dio? dio}) : _dio = dio ?? buildDio(), super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await readToken();
    if (token != null) {
      state = state.copyWith(isLoggedIn: true, token: token);
    }
  }

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
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return 'Login failed. Check your connection and try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);

final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authProvider).isLoggedIn,
);

final currentUserProvider = Provider<Map<String, dynamic>?>(
  (ref) => ref.watch(authProvider).user,
);
