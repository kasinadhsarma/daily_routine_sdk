import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';
import 'package:daily_routine_sdk/routines/implementations/rest_routine_repository_service.dart';
import 'package:daily_routine_sdk/routines/routine_repository_service.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// [RoutineRepositoryService] backed by Firestore — or, on platforms with
/// no native `cloud_firestore` plugin implementation (Linux desktop), by
/// [RestRoutineRepositoryService] instead. Stored at
/// `users/{uid}/tasks/{taskId}` either way.
class FirestoreRoutineRepositoryService implements RoutineRepositoryService {
  factory FirestoreRoutineRepositoryService({FirebaseFirestore? firestore}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return FirestoreRoutineRepositoryService._(RestRoutineRepositoryService());
    }
    return FirestoreRoutineRepositoryService._(
      _NativeFirestoreRoutineRepositoryService(firestore: firestore),
    );
  }

  FirestoreRoutineRepositoryService._(this._impl);

  final RoutineRepositoryService _impl;

  @override
  Stream<List<RoutineTask>> watchTasks(String uid) => _impl.watchTasks(uid);

  @override
  Future<Result<void>> upsertTask(String uid, RoutineTask task) =>
      _impl.upsertTask(uid, task);

  @override
  Future<Result<void>> deleteTask(String uid, String taskId) =>
      _impl.deleteTask(uid, taskId);

  @override
  Future<Result<void>> setTaskCompleted(
    String uid,
    String taskId, {
    required bool isCompleted,
  }) => _impl.setTaskCompleted(uid, taskId, isCompleted: isCompleted);
}

class _NativeFirestoreRoutineRepositoryService implements RoutineRepositoryService {
  _NativeFirestoreRoutineRepositoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _tasksRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('tasks');

  @override
  Stream<List<RoutineTask>> watchTasks(String uid) {
    return _tasksRef(uid).orderBy('startMinuteOfDay').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => RoutineTask.fromJson({...doc.data(), 'id': doc.id}))
          .toList(),
    );
  }

  @override
  Future<Result<void>> upsertTask(String uid, RoutineTask task) =>
      _guard(() async {
        final now = DateTime.now();
        final data =
            task.copyWith(updatedAt: now, createdAt: task.createdAt ?? now).toJson()
              ..remove('id');
        await _tasksRef(uid).doc(task.id).set(data, SetOptions(merge: true));
      });

  @override
  Future<Result<void>> deleteTask(String uid, String taskId) =>
      _guard(() => _tasksRef(uid).doc(taskId).delete());

  @override
  Future<Result<void>> setTaskCompleted(
    String uid,
    String taskId, {
    required bool isCompleted,
  }) => _guard(
    () => _tasksRef(uid).doc(taskId).update({
      'isCompletedToday': isCompleted,
      'updatedAt': DateTime.now().toIso8601String(),
    }),
  );

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
