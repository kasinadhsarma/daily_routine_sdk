import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/activity/activity_repository_service.dart';
import 'package:daily_routine_sdk/activity/implementations/rest_activity_repository_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/models/activity_event.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// [ActivityRepositoryService] backed by Firestore — or, on platforms with
/// no native `cloud_firestore` plugin implementation (Linux desktop), by
/// [RestActivityRepositoryService] instead. Stored at
/// `users/{uid}/activity/{eventId}` either way — the same collection the
/// Chrome extension writes browser sessions into.
class FirestoreActivityRepositoryService implements ActivityRepositoryService {
  factory FirestoreActivityRepositoryService({FirebaseFirestore? firestore}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return FirestoreActivityRepositoryService._(RestActivityRepositoryService());
    }
    return FirestoreActivityRepositoryService._(
      _NativeFirestoreActivityRepositoryService(firestore: firestore),
    );
  }

  FirestoreActivityRepositoryService._(this._impl);

  final ActivityRepositoryService _impl;

  @override
  Future<Result<void>> logAppUsage(String uid, AppUsageEvent event) =>
      _impl.logAppUsage(uid, event);

  @override
  Stream<List<ActivityEvent>> watchRecentActivity(String uid, {int limit = 50}) =>
      _impl.watchRecentActivity(uid, limit: limit);
}

class _NativeFirestoreActivityRepositoryService implements ActivityRepositoryService {
  _NativeFirestoreActivityRepositoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('users').doc(uid).collection('activity');

  @override
  Future<Result<void>> logAppUsage(String uid, AppUsageEvent event) => _guard(() async {
    await _ref(uid).add({
      'source': _source,
      'type': 'app',
      'packageName': event.packageName,
      'title': event.appLabel,
      if (event.windowTitle != null) 'windowTitle': event.windowTitle,
      if (!kIsWeb && !Platform.isAndroid) 'platform': Platform.operatingSystem,
      'startedAt': Timestamp.fromDate(event.startedAt),
      'durationMs': event.durationMs,
    });
  });

  /// `android` for the mobile app-usage tracker, `desktop` for the Linux/
  /// Windows/macOS one (see `platform` field for which OS), matching the
  /// `chrome` source the browser extension writes.
  String get _source {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    return 'desktop';
  }

  @override
  Stream<List<ActivityEvent>> watchRecentActivity(String uid, {int limit = 50}) {
    return _ref(uid)
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ActivityEvent.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

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
