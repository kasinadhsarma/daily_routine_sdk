import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:daily_routine_sdk/blocked_apps/blocked_apps_repository_service.dart';
import 'package:daily_routine_sdk/config/rest_firebase_config.dart';
import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/firestore_rest/firestore_rest_codec.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';
import 'package:http/http.dart' as http;

/// [BlockedAppsRepositoryService] backed directly by the Firestore REST API
/// v1, for platforms with no native `cloud_firestore` plugin implementation
/// (Linux desktop — see `FirestoreBlockedAppsRepositoryService`, which
/// dispatches to this on Linux). Polls on an interval instead of a true
/// push channel — see `RestRoutineRepositoryService`'s doc comment.
class RestBlockedAppsRepositoryService implements BlockedAppsRepositoryService {
  RestBlockedAppsRepositoryService({
    http.Client? client,
    this.pollInterval = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  static const _logName = 'RestBlockedAppsRepositoryService';

  final http.Client _client;
  final Duration pollInterval;

  final Map<String, StreamController<List<BlockedApp>>> _watchControllers = {};
  final Map<String, Timer> _pollTimers = {};

  String _baseUrl(String uid) =>
      'https://firestore.googleapis.com/v1/projects/'
      '${RestFirebaseConfig.current.projectId}/databases/(default)/documents/'
      'users/$uid/blockedApps';

  Future<Map<String, String>> _headers() async {
    final token = await RestFirebaseConfig.current.idTokenProvider?.call();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Stream<List<BlockedApp>> watchBlockedApps(String uid) {
    final existing = _watchControllers[uid];
    if (existing != null) return existing.stream;

    late final StreamController<List<BlockedApp>> controller;
    controller = StreamController<List<BlockedApp>>.broadcast(
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
      developer.log('Polling users/$uid/blockedApps', name: _logName);
      final response = await _client.get(
        Uri.parse(_baseUrl(uid)),
        headers: await _headers(),
      );
      if (response.statusCode != 200) {
        developer.log(
          'Poll failed: ${response.statusCode} ${response.body}',
          name: _logName,
          level: 900,
        );
        controller.addError(
          StateError(
            'Firestore REST watchBlockedApps failed: ${response.statusCode} ${response.body}',
          ),
        );
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = body['documents'] as List<dynamic>? ?? const [];
      developer.log('Fetched ${docs.length} blocked-app doc(s)', name: _logName);
      controller.add(
        docs
            .map((doc) => BlockedApp.fromJson(decodeFirestoreFields(doc as Map<String, dynamic>)))
            .toList(),
      );
    } catch (e, stackTrace) {
      developer.log('Poll threw', name: _logName, level: 1000, error: e, stackTrace: stackTrace);
      controller.addError(e, stackTrace);
    }
  }

  @override
  Future<Result<void>> setBlockedApps(String uid, List<BlockedApp> apps) async {
    try {
      for (final app in apps) {
        final response = await _client.patch(
          Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(app.packageId)}'),
          headers: await _headers(),
          body: jsonEncode({'fields': encodeFirestoreFields(app.toJson())}),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return Result.failure(
            DatabaseError(
              'Firestore REST setBlockedApps failed: ${response.statusCode} ${response.body}',
            ),
          );
        }
      }
      return const Result.success(null);
    } catch (e, stackTrace) {
      return Result.failure(
        UnknownError('Unexpected database error.', cause: e, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> removeBlockedApp(String uid, String packageId) async {
    try {
      final response = await _client.delete(
        Uri.parse('${_baseUrl(uid)}/${Uri.encodeComponent(packageId)}'),
        headers: await _headers(),
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        return Result.failure(
          DatabaseError(
            'Firestore REST removeBlockedApp failed: ${response.statusCode} ${response.body}',
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
