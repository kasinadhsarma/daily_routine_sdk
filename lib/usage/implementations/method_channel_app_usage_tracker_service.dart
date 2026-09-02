import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/usage/app_usage_tracker_service.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Android implementation. Shares the same `MethodChannel` as
/// `MethodChannelAppBlockerService` (both talk to `AppBlockerPlugin`, and
/// usage access is the same OS permission the blocker already needs), with
/// its own `EventChannel` for session-ended events.
class MethodChannelAppUsageTrackerService extends AppUsageTrackerService {
  MethodChannelAppUsageTrackerService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('daily_routine_sdk/app_blocker'),
       _eventChannel =
           eventChannel ??
           const EventChannel('daily_routine_sdk/app_usage/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isSupported() async => _isAndroid;

  @override
  Future<bool> hasPermission() async {
    if (!_isAndroid) return false;
    final result = await _methodChannel.invokeMethod<bool>('hasUsageAccess');
    return result ?? false;
  }

  @override
  Future<void> requestPermission() async {
    if (!_isAndroid) return;
    await _methodChannel.invokeMethod<void>('requestUsageAccess');
  }

  @override
  Future<void> startTracking() async {
    if (!_isAndroid) return;
    await _methodChannel.invokeMethod<void>('startUsageTracking');
  }

  @override
  Future<void> stopTracking() async {
    if (!_isAndroid) return;
    await _methodChannel.invokeMethod<void>('stopUsageTracking');
  }

  @override
  Stream<AppUsageEvent> get events {
    if (!_isAndroid) return const Stream.empty();
    return _eventChannel.receiveBroadcastStream().map((raw) {
      final map = (raw as Map).cast<String, Object?>();
      return AppUsageEvent(
        packageName: map['packageName'] as String,
        appLabel: map['appLabel'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(map['startedAt'] as int),
        durationMs: map['durationMs'] as int,
      );
    });
  }
}
