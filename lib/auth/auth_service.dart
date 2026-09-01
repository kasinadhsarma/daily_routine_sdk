import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_user.dart';

/// Platform-abstraction boundary for authentication — app code never talks
/// to `firebase_auth` directly, only [AppUser] crosses this boundary.
abstract class AuthService {
  /// Emits [AppUser.empty] when signed out, and the current user otherwise.
  /// Emits immediately with the current state on listen.
  Stream<AppUser> authStateChanges();

  AppUser get currentUser;

  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<Result<void>> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  });

  /// Signs in via Google, using Firebase Auth's native provider flow
  /// (Credential Manager on Android, native web-view on iOS/macOS, popup on
  /// web) — no separate `google_sign_in` package needed. **Not supported on
  /// Linux/Windows**: `firebase_auth` has no plugin implementation for
  /// those platforms at all (every method on this class fails there, not
  /// just this one).
  Future<Result<void>> signInWithGoogle();

  Future<Result<void>> sendPasswordResetEmail(String email);

  Future<void> signOut();
}
