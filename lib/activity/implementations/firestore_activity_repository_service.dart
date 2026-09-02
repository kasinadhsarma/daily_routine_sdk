import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/activity/activity_repository_service.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/models/activity_event.dart';

/// [ActivityRepositoryService] backed by Firestore, at
/// `users/{uid}/activity/{eventId}` — the same collection the Chrome
/// extension writes browser sessions into.
class FirestoreActivityRepositoryService implements ActivityRepositoryService {
  FirestoreActivityRepositoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('users').doc(uid).collection('activity');

  @override
  Future<Result<void>> logAppUsage(String uid, AppUsageEvent event) => _guard(() async {
    await _ref(uid).add({
      'source': 'android',
      'type': 'app',
      'packageName': event.packageName,
      'title': event.appLabel,
      'startedAt': Timestamp.fromDate(event.startedAt),
      'durationMs': event.durationMs,
    });
  });

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
