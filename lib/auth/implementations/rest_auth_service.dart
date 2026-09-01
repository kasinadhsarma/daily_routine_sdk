import 'dart:async';
import 'dart:convert';

import 'package:daily_routine_sdk/auth/auth_service.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_user.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// [AuthService] backed directly by Firebase's Identity Toolkit + Secure
/// Token REST APIs, for platforms with no native `firebase_auth` plugin
/// implementation (Linux desktop — see `FirebaseAuthService`, which
/// dispatches to this on Linux).
///
/// Session persistence (silent restore across app launches) is handled
/// manually here via `flutter_secure_storage` — the native SDK does this
/// itself; REST doesn't, so this class owns it.
class RestAuthService implements AuthService {
  RestAuthService({FlutterSecureStorage? secureStorage, http.Client? client})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
      _client = client ?? http.Client() {
    RestFirebaseConfig.current.idTokenProvider = _validIdToken;
    unawaited(_restoreSession());
  }

  static const _refreshTokenKey = 'daily_routine_rest_auth_refresh_token';

  final FlutterSecureStorage _secureStorage;
  final http.Client _client;
  final _authStateController = StreamController<AppUser>.broadcast();

  AppUser _currentUser = AppUser.empty;
  String? _idToken;
  String? _refreshToken;
  DateTime? _idTokenExpiry;

  String get _apiKey => RestFirebaseConfig.current.apiKey;

  @override
  AppUser get currentUser => _currentUser;

  @override
  Stream<AppUser> authStateChanges() => _authStateController.stream;

  void _setSession({
    required String uid,
    String? email,
    String? displayName,
    required String idToken,
    required String refreshToken,
    required int expiresInSeconds,
  }) {
    _idToken = idToken;
    _refreshToken = refreshToken;
    _idTokenExpiry = DateTime.now().add(Duration(seconds: expiresInSeconds));
    _currentUser = AppUser(uid: uid, email: email, displayName: displayName);
    _authStateController.add(_currentUser);
    unawaited(_secureStorage.write(key: _refreshTokenKey, value: refreshToken));
  }

  void _clearSession() {
    _idToken = null;
    _refreshToken = null;
    _idTokenExpiry = null;
    _currentUser = AppUser.empty;
    _authStateController.add(AppUser.empty);
  }

  Future<void> _restoreSession() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      _authStateController.add(AppUser.empty);
      return;
    }
    if (!await _refresh(refreshToken)) {
      _authStateController.add(AppUser.empty);
    }
  }

  /// Exchanges a refresh token for a new ID token via the Secure Token API
  /// and repopulates the session (including a fresh account lookup for
  /// email/displayName, which the refresh response doesn't carry).
  Future<bool> _refresh(String refreshToken) async {
    try {
      final response = await _client.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
        body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      );
      if (response.statusCode != 200) {
        _clearSession();
        return false;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final idToken = body['id_token'] as String;
      final account = await _lookupAccount(idToken);
      if (account == null) {
        _clearSession();
        return false;
      }
      _setSession(
        uid: account.uid,
        email: account.email,
        displayName: account.displayName,
        idToken: idToken,
        refreshToken: body['refresh_token'] as String,
        expiresInSeconds: int.parse(body['expires_in'] as String),
      );
      return true;
    } catch (_) {
      _clearSession();
      return false;
    }
  }

  Future<AppUser?> _lookupAccount(String idToken) async {
    final response = await _client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$_apiKey',
      ),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final users = body['users'] as List<dynamic>?;
    if (users == null || users.isEmpty) return null;
    final user = users.first as Map<String, dynamic>;
    return AppUser(
      uid: user['localId'] as String,
      email: user['email'] as String?,
      displayName: user['displayName'] as String?,
    );
  }

  /// A currently-valid ID token, refreshing first if it's within a minute
  /// of expiry — this is what `RestFirebaseConfig.idTokenProvider` points
  /// at, so Firestore REST calls always get a live token.
  Future<String?> _validIdToken() async {
    final refreshToken = _refreshToken;
    if (_idToken == null || refreshToken == null) return null;
    final expiry = _idTokenExpiry;
    if (expiry == null ||
        DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)))) {
      if (!await _refresh(refreshToken)) return null;
    }
    return _idToken;
  }

  Future<Result<void>> _passwordAuth(
    String endpoint,
    String email,
    String password,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:$endpoint?key=$_apiKey',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return Result.failure(_mapAuthError(response.statusCode, body));
      }
      _setSession(
        uid: body['localId'] as String,
        email: body['email'] as String?,
        displayName: body['displayName'] as String?,
        idToken: body['idToken'] as String,
        refreshToken: body['refreshToken'] as String,
        expiresInSeconds: int.parse(body['expiresIn'] as String),
      );
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected authentication error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _passwordAuth('signInWithPassword', email, password);

  @override
  Future<Result<void>> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final result = await _passwordAuth('signUp', email, password);
    if (result.isFailure || displayName == null || displayName.isEmpty) {
      return result;
    }
    return _updateDisplayName(displayName);
  }

  Future<Result<void>> _updateDisplayName(String displayName) async {
    final idToken = _idToken;
    if (idToken == null) return const Result.success(null);
    try {
      final response = await _client.post(
        Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:update?key=$_apiKey',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
          'displayName': displayName,
          'returnSecureToken': false,
        }),
      );
      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return Result.failure(_mapAuthError(response.statusCode, body));
      }
      _currentUser = AppUser(
        uid: _currentUser.uid,
        email: _currentUser.email,
        displayName: displayName,
      );
      _authStateController.add(_currentUser);
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected authentication error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> signInWithGoogle() async {
    return const Result.failure(
      AuthError(
        "Google sign-in isn't available on Linux desktop — firebase_auth has "
        'no native plugin there. Use email and password instead.',
        code: 'unsupported-platform',
      ),
    );
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    try {
      final response = await _client.post(
        Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$_apiKey',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
      );
      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return Result.failure(_mapAuthError(response.statusCode, body));
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected authentication error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _secureStorage.delete(key: _refreshTokenKey);
    _clearSession();
  }

  AppError _mapAuthError(int statusCode, Map<String, dynamic> body) {
    final code =
        (body['error'] as Map<String, dynamic>?)?['message'] as String? ??
        'HTTP $statusCode';
    return AuthError(code, code: code);
  }
}
