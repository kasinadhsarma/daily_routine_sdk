import 'package:daily_routine_sdk/auth/auth_service.dart';
import 'package:daily_routine_sdk/auth/implementations/rest_auth_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_user.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// [AuthService] backed by Firebase Auth — or, on platforms with no native
/// `firebase_auth` plugin implementation (Linux desktop), by
/// [RestAuthService] instead. The choice is made once, here, at
/// construction; every call site elsewhere is unaffected.
class FirebaseAuthService implements AuthService {
  factory FirebaseAuthService({fb.FirebaseAuth? firebaseAuth}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return FirebaseAuthService._(RestAuthService());
    }
    return FirebaseAuthService._(_NativeFirebaseAuthService(firebaseAuth: firebaseAuth));
  }

  FirebaseAuthService._(this._impl);

  final AuthService _impl;

  @override
  Stream<AppUser> authStateChanges() => _impl.authStateChanges();

  @override
  AppUser get currentUser => _impl.currentUser;

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _impl.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<Result<void>> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) => _impl.signUpWithEmailAndPassword(
    email: email,
    password: password,
    displayName: displayName,
  );

  @override
  Future<Result<void>> signInWithGoogle() => _impl.signInWithGoogle();

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) =>
      _impl.sendPasswordResetEmail(email);

  @override
  Future<void> signOut() => _impl.signOut();
}

/// The original, unchanged Firebase Auth SDK-backed implementation —
/// wrapped by the dispatcher above.
class _NativeFirebaseAuthService implements AuthService {
  _NativeFirebaseAuthService({fb.FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _firebaseAuth;

  @override
  Stream<AppUser> authStateChanges() =>
      _firebaseAuth.authStateChanges().map(_toAppUser);

  @override
  AppUser get currentUser => _toAppUser(_firebaseAuth.currentUser);

  AppUser _toAppUser(fb.User? user) {
    if (user == null) return AppUser.empty;
    return AppUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _guard(
    () => _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    ),
  );

  @override
  Future<Result<void>> signUpWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) => _guard(() async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (displayName != null && displayName.isNotEmpty) {
      await credential.user?.updateDisplayName(displayName);
    }
  });

  @override
  Future<Result<void>> signInWithGoogle() =>
      _guard(() => _firebaseAuth.signInWithProvider(fb.GoogleAuthProvider()));

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) =>
      _guard(() => _firebaseAuth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() => _firebaseAuth.signOut();

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Result.success(null);
    } on fb.FirebaseAuthException catch (e, st) {
      return Result.failure(
        AuthError(
          e.message ?? 'Authentication failed.',
          code: e.code,
          cause: e,
          stackTrace: st,
        ),
      );
    } catch (e, st) {
      return Result.failure(
        UnknownError('Unexpected authentication error.', cause: e, stackTrace: st),
      );
    }
  }
}
