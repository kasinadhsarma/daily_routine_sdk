import 'package:daily_routine_sdk/blocking/app_blocker_service.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';
import 'package:flutter/services.dart';

/// Android implementation, talking to the Kotlin side over a
/// [MethodChannel] + [EventChannel] pair. The native side runs a foreground
/// service that polls `UsageStatsManager` for the current foreground app and
/// brings the host app to the front (as a "blocked" screen) whenever a
/// blocklisted package is detected.
class MethodChannelAppBlockerService extends AppBlockerService {
  MethodChannelAppBlockerService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('daily_routine_sdk/app_blocker'),
       _eventChannel =
           eventChannel ??
           const EventChannel('daily_routine_sdk/app_blocker/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Future<bool> isPermissionRequired() async => true;

  @override
  Future<bool> hasPermission() async {
    final result = await _methodChannel.invokeMethod<bool>('hasUsageAccess');
    return result ?? false;
  }

  @override
  Future<void> requestPermission() async {
    await _methodChannel.invokeMethod<void>('requestUsageAccess');
  }

  @override
  Future<List<BlockedApp>> getBlockableTargets() async {
    final result = await _methodChannel.invokeMethod<List<Object?>>(
      'getInstalledApps',
    );
    if (result == null) return const [];
    return result
        .cast<Map<Object?, Object?>>()
        .map(
          (raw) => BlockedApp(
            packageId: raw['packageId'] as String,
            displayName: raw['displayName'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> startBlocking(List<String> packageIds) async {
    await _methodChannel.invokeMethod<void>('startBlocking', {
      'packageIds': packageIds,
    });
  }

  @override
  Future<void> stopBlocking() async {
    await _methodChannel.invokeMethod<void>('stopBlocking');
  }

  @override
  Stream<String> get onAppBlocked =>
      _eventChannel.receiveBroadcastStream().cast<String>();
}
