import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/blocked_apps/blocked_apps_repository_service.dart';
import 'package:daily_routine_sdk/blocked_apps/implementations/rest_blocked_apps_repository_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// [BlockedAppsRepositoryService] backed by Firestore — or, on platforms
/// with no native `cloud_firestore` plugin implementation (Linux desktop),
/// by [RestBlockedAppsRepositoryService] instead. Stored at
/// `users/{uid}/blockedApps/{packageId}` either way.
class FirestoreBlockedAppsRepositoryService
    implements BlockedAppsRepositoryService {
  factory FirestoreBlockedAppsRepositoryService({FirebaseFirestore? firestore}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return FirestoreBlockedAppsRepositoryService._(RestBlockedAppsRepositoryService());
    }
    return FirestoreBlockedAppsRepositoryService._(
      _NativeFirestoreBlockedAppsRepositoryService(firestore: firestore),
    );
  }

  FirestoreBlockedAppsRepositoryService._(this._impl);

  final BlockedAppsRepositoryService _impl;

  @override
  Stream<List<BlockedApp>> watchBlockedApps(String uid) => _impl.watchBlockedApps(uid);

  @override
  Future<Result<void>> setBlockedApps(String uid, List<BlockedApp> apps) =>
      _impl.setBlockedApps(uid, apps);

  @override
  Future<Result<void>> removeBlockedApp(String uid, String packageId) =>
      _impl.removeBlockedApp(uid, packageId);
}

class _NativeFirestoreBlockedAppsRepositoryService
    implements BlockedAppsRepositoryService {
  _NativeFirestoreBlockedAppsRepositoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('users').doc(uid).collection('blockedApps');

  @override
  Stream<List<BlockedApp>> watchBlockedApps(String uid) {
    return _ref(uid).snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => BlockedApp.fromJson(doc.data())).toList(),
    );
  }

  @override
  Future<Result<void>> setBlockedApps(String uid, List<BlockedApp> apps) =>
      _guard(() async {
        final batch = _firestore.batch();
        for (final app in apps) {
          batch.set(_ref(uid).doc(app.packageId), app.toJson());
        }
        await batch.commit();
      });

  @override
  Future<Result<void>> removeBlockedApp(String uid, String packageId) =>
      _guard(() => _ref(uid).doc(packageId).delete());

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Result.success(null);
    } on FirebaseException catch (e, st) {
      return Result.failure(
        DatabaseError(e.message ?? 'Database operation failed.', cause: e, stackTrace: st),
      );
    } catch (e, st) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: st),
      );
    }
  }
}
