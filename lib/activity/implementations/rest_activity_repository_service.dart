import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:daily_routine_sdk/activity/activity_repository_service.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/models/activity_event.dart';
import 'package:daily_routine_sdk/models/activity_summary.dart';
import 'package:http/http.dart' as http;

/// [ActivityRepositoryService] backed directly by the Firestore REST API v1,
/// for platforms with no native `cloud_firestore` plugin implementation
/// (Linux desktop — see `FirestoreActivityRepositoryService`, which
/// dispatches to this on Linux). Polls on an interval instead of a true
/// push channel — see `RestRoutineRepositoryService`'s doc comment.
class RestActivityRepositoryService implements ActivityRepositoryService {
  RestActivityRepositoryService({
    http.Client? client,
    this.pollInterval = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration pollInterval;

  static const _logName = 'RestActivityRepositoryService';

  final Map<String, StreamController<List<ActivityEvent>>> _watchControllers = {};
  final Map<String, Timer> _pollTimers = {};
  final Map<String, int> _limits = {};

  String get _projectRoot =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents';

  String _baseUrl(String uid) => '$_projectRoot/users/$uid/activity';

  String _summariesUrl(String uid) => '$_projectRoot/users/$uid/activitySummaries';

  String _rolloverMarkerUrl(String uid) => '$_projectRoot/users/$uid/meta/activityRollover';

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
      // Firestore's listDocuments endpoint defaults to returning the whole
      // collection with no limit — for an activity log that grows by the
      // minute, that meant downloading everything (hundreds+ of docs) on
      // every 10-second poll, forever. pageSize + orderBy push the
      // limiting down to Firestore itself, matching what the native SDK's
      // .orderBy().limit() already does on other platforms; without this,
      // the read volume blows through the free-tier daily quota (50k
      // reads/day) in well under an hour once the log has any real size.
      final limit = _limits[uid] ?? 50;
      final uri = Uri.parse(_baseUrl(uid)).replace(
        queryParameters: {
          'pageSize': '$limit',
          'orderBy': 'startedAt desc',
        },
      );
      developer.log('Polling users/$uid/activity (pageSize=$limit)', name: _logName);
      final response = await _client.get(uri, headers: await _headers());
      if (response.statusCode != 200) {
        developer.log(
          'Poll failed: ${response.statusCode} ${response.body}',
          name: _logName,
          level: 900,
        );
        controller.addError(
          StateError(
            'Firestore REST watchRecentActivity failed: ${response.statusCode} ${response.body}',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      developer.log('Fetched ${docs.length} activity doc(s)', name: _logName);
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
      controller.add(events.take(limit).toList());
    } catch (e, stackTrace) {
      developer.log('Poll threw', name: _logName, level: 1000, error: e, stackTrace: stackTrace);
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<Result<List<ActivityEvent>>> fetchAllEvents(String uid) async {
    try {
      final events = <ActivityEvent>[];
      String? pageToken;
      do {
        final queryParameters = <String, String>{'pageSize': '1000'};
        final token = pageToken;
        if (token != null) queryParameters['pageToken'] = token;
        final uri = Uri.parse(_baseUrl(uid)).replace(queryParameters: queryParameters);
        final response = await _client.get(uri, headers: await _headers());
        if (response.statusCode != 200) {
          return Result.failure(
            DatabaseError(
              'Firestore REST fetchAllEvents failed: ${response.statusCode} ${response.body}',
            ),
          );
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final docs = body['documents'] as List<dynamic>? ?? const [];
        events.addAll(
          docs.map((doc) {
            final map = doc as Map<String, dynamic>;
            final id = (map['name'] as String).split('/').last;
            return ActivityEvent.fromFirestore(id, decodeFirestoreFields(map));
          }),
        );
        pageToken = body['nextPageToken'] as String?;
      } while (pageToken != null);
      developer.log('fetchAllEvents: ${events.length} doc(s)', name: _logName);
      return Result.success(events);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> deleteEvents(String uid, List<String> eventIds) async {
    try {
      // No batch-delete over plain REST — fire a bounded number of
      // concurrent DELETEs at a time rather than either one-at-a-time
      // (slow for a large backlog) or all-at-once (could trip Firestore's
      // per-second write rate limits).
      const concurrency = 20;
      final headers = await _headers();
      for (var i = 0; i < eventIds.length; i += concurrency) {
        final chunk = eventIds.skip(i).take(concurrency);
        await Future.wait(
          chunk.map(
            (id) => _client.delete(
              Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(id)}'),
              headers: headers,
            ),
          ),
        );
      }
      developer.log('Deleted ${eventIds.length} event doc(s)', name: _logName);
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> saveDailySummary(String uid, ActivitySummary summary) async {
    try {
      final response = await _client.patch(
        Uri.parse('${_summariesUrl(uid)}/${Uri.encodeComponent(summary.date)}'),
        headers: await _headers(),
        body: jsonEncode({'fields': encodeFirestoreFields(summary.toJson())}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          DatabaseError(
            'Firestore REST saveDailySummary failed: ${response.statusCode} ${response.body}',
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

  @override
  Future<Result<ActivitySummary?>> getDailySummary(String uid, String date) async {
    try {
      final response = await _client.get(
        Uri.parse('${_summariesUrl(uid)}/${Uri.encodeComponent(date)}'),
        headers: await _headers(),
      );
      if (response.statusCode == 404) return const Result.success(null);
      if (response.statusCode != 200) {
        return Result.failure(
          DatabaseError(
            'Firestore REST getDailySummary failed: ${response.statusCode} ${response.body}',
          ),
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return Result.success(ActivitySummary.fromJson(decodeFirestoreFields(body)));
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<String?>> getLastRolloverDate(String uid) async {
    try {
      final response = await _client.get(
        Uri.parse(_rolloverMarkerUrl(uid)),
        headers: await _headers(),
      );
      if (response.statusCode == 404) return const Result.success(null);
      if (response.statusCode != 200) {
        return Result.failure(
          DatabaseError(
            'Firestore REST getLastRolloverDate failed: ${response.statusCode} ${response.body}',
          ),
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = decodeFirestoreFields(body);
      return Result.success(fields['lastRolloverDate'] as String?);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> setLastRolloverDate(String uid, String date) async {
    try {
      final response = await _client.patch(
        Uri.parse(_rolloverMarkerUrl(uid)),
        headers: await _headers(),
        body: jsonEncode({
          'fields': encodeFirestoreFields({'lastRolloverDate': date}),
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Result.failure(
          DatabaseError(
            'Firestore REST setLastRolloverDate failed: ${response.statusCode} ${response.body}',
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
