import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daily_routine_sdk/activity/activity_repository_service.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/models/activity_event.dart';
import 'package:http/http.dart' as http;

/// [ActivityRepositoryService] backed directly by the Firestore REST API v1,
/// for platforms with no native `cloud_firestore` plugin implementation
/// (Linux desktop — see `FirestoreActivityRepositoryService`, which
/// dispatches to this on Linux). Polls on an interval instead of a true
/// push channel — see `RestRoutineRepositoryService`'s doc comment.
class RestActivityRepositoryService implements ActivityRepositoryService {
  RestActivityRepositoryService({
    http.Client? client,
    this.pollInterval = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration pollInterval;

  final Map<String, StreamController<List<ActivityEvent>>> _watchControllers = {};
  final Map<String, Timer> _pollTimers = {};
  final Map<String, int> _limits = {};

  String _baseUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/activity';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Future<Result<void>> logAppUsage(String uid, AppUsageEvent event) async {
    try {
      final data = {
        'source': _source,
        'type': 'app',
        'packageName': event.packageName,
        'title': event.appLabel,
        if (event.windowTitle != null) 'windowTitle': event.windowTitle,
        if (!Platform.isAndroid) 'platform': Platform.operatingSystem,
        'startedAt': event.startedAt.toIso8601String(),
        'durationMs': event.durationMs,
      };
      final response = await _client.post(
        Uri.parse(_baseUrl(uid)),
        headers: await _headers(),
        body: jsonEncode({'fields': encodeFirestoreFields(data)}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          DatabaseError(
            'Firestore REST logAppUsage failed: ${response.statusCode} ${response.body}',
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

  String get _source => Platform.isAndroid ? 'android' : 'desktop';

  @override
  Stream<List<ActivityEvent>> watchRecentActivity(String uid, {int limit = 50}) {
    _limits[uid] = limit;
    final existing = _watchControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<ActivityEvent>> controller;
    controller = StreamController<List<ActivityEvent>>.broadcast(
      onListen: () {
        _pollTimers[uid] ??= Timer.periodic(pollInterval, (_) => _pollOnce(uid));
        unawaited(_pollOnce(uid));
      },
      onCancel: () {
        _pollTimers.remove(uid)?.cancel();
        _watchControllers.remove(uid);
        _limits.remove(uid);
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
          StateError(
            'Firestore REST watchRecentActivity failed: ${response.statusCode} ${response.body}',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      final events = docs.map((doc) {
        final map = doc as Map<String, dynamic>;
        final id = (map['name'] as String).split('/').last;
        return ActivityEvent.fromFirestore(id, decodeFirestoreFields(map));
      }).toList()
        ..sort((a, b) {
          final aTime = a.startedAt;
          final bTime = b.startedAt;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });
      final limit = _limits[uid] ?? 50;
      controller.add(events.take(limit).toList());
    } catch (e, stackTrace) {
      controller.addError(e, stackTrace);
    }
  }
}
