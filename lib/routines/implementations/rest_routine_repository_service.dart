import 'dart:async';
import 'dart:convert';

import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';
import 'package:daily_routine_sdk/routines/routine_repository_service.dart';
import 'package:http/http.dart' as http;

/// [RoutineRepositoryService] backed directly by the Firestore REST API v1,
/// for platforms with no native `cloud_firestore` plugin implementation
/// (Linux desktop — see `FirestoreRoutineRepositoryService`, which
/// dispatches to this on Linux).
///
/// [watchTasks] has no true push channel available over plain REST —
/// Firestore's real-time Listen API is a bidirectional gRPC/HTTP2 stream,
/// not reasonably implementable with `package:http`. This polls on an
/// interval instead: a disclosed, deliberate degradation (near-live, not
/// push).
class RestRoutineRepositoryService implements RoutineRepositoryService {
  RestRoutineRepositoryService({
    http.Client? client,
    this.pollInterval = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration pollInterval;

  final Map<String, StreamController<List<RoutineTask>>> _watchControllers = {};
  final Map<String, Timer> _pollTimers = {};

  String _baseUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/tasks';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Stream<List<RoutineTask>> watchTasks(String uid) {
    final existing = _watchControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<RoutineTask>> controller;
    controller = StreamController<List<RoutineTask>>.broadcast(
      onListen: () {
        _pollTimers[uid] ??= Timer.periodic(pollInterval, (_) => _pollOnce(uid));
        unawaited(_pollOnce(uid));
      },
      onCancel: () {
        _pollTimers.remove(uid)?.cancel();
        _watchControllers.remove(uid);
      },
    );
    _watchControllers[uid] = controller;
    return controller.stream;
  }

  Future<void> _pollOnce(String uid) async {
    final controller = _watchControllers[uid];
    if (controller == null || controller.isClosed) return;
    try {
      final response = await _client.get(
        Uri.parse(_baseUrl(uid)),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        controller.addError(
          StateError('Firestore REST watchTasks failed: ${response.statusCode} ${response.body}'),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      final tasks = docs.map((doc) {
        final map = doc as Map<String, dynamic>;
        final id = (map['name'] as String).split('/').last;
        return RoutineTask.fromJson({...decodeFirestoreFields(map), 'id': id});
      }).toList()..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));
      controller.add(tasks);
    } catch (e, stackTrace) {
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<Result<void>> upsertTask(String uid, RoutineTask task) async {
    try {
      final now = DateTime.now();
      final data =
          task.copyWith(updatedAt: now, createdAt: task.createdAt ?? now).toJson()
            ..remove('id');
      final response = await _client.patch(
        Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(task.id)}'),
        headers: await _headers(),
        body: jsonEncode({'fields': encodeFirestoreFields(data)}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          DatabaseError('Firestore REST upsertTask failed: ${response.statusCode} ${response.body}'),
        );
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> deleteTask(String uid, String taskId) async {
    try {
      final response = await _client.delete(
        Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(taskId)}'),
        headers: await _headers(),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        return Result.failure(
          DatabaseError('Firestore REST deleteTask failed: ${response.statusCode} ${response.body}'),
        );
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> setTaskCompleted(
    String uid,
    String taskId, {
    required bool isCompleted,
  }) async {
    try {
      final fields = encodeFirestoreFields({
        'isCompletedToday': isCompleted,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      final uri = Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(taskId)}').replace(
        queryParameters: {
          'updateMask.fieldPaths': ['isCompletedToday', 'updatedAt'],
        },
      );
      final response = await _client.patch(
        uri,
        headers: await _headers(),
        body: jsonEncode({'fields': fields}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          DatabaseError(
            'Firestore REST setTaskCompleted failed: ${response.statusCode} ${response.body}',
          ),
        );
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }
}
