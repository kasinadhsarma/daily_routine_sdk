import 'dart:async';
import 'dart:io';

import 'package:daily_routine_sdk/blocking/app_blocker_service.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';
import 'package:daily_routine_sdk/usage/app_usage_tracker_service.dart';
import 'package:daily_routine_sdk/usage/implementations/desktop_app_usage_tracker_service.dart';

/// Desktop (Linux/Windows/macOS) implementation.
///
/// There is no OS "block this app" API on desktop, so this works by polling
/// the running process list every couple of seconds and killing any process
/// whose executable name matches the active blocklist. This only blocks
/// apps that are already running and only while this app is running; it is
/// a deterrent, not a hard sandbox.
class DesktopAppBlockerService extends AppBlockerService {
  DesktopAppBlockerService();

  static void registerWith() {
    AppBlockerService.instance = DesktopAppBlockerService();
    AppUsageTrackerService.instance = DesktopAppUsageTrackerService();
  }

  Timer? _pollTimer;
  Set<String> _blockedProcessNames = {};
  final StreamController<String> _blockedController =
      StreamController<String>.broadcast();

  @override
  Future<bool> isPermissionRequired() async => false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<List<BlockedApp>> getBlockableTargets() async {
    final names = await _runningProcessNames();
    return names
        .map((name) => BlockedApp(packageId: name, displayName: name))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Future<void> startBlocking(List<String> packageIds) async {
    _blockedProcessNames = packageIds.toSet();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  @override
  Future<void> stopBlocking() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _blockedProcessNames = {};
  }

  @override
  Stream<String> get onAppBlocked => _blockedController.stream;

  Future<void> _tick() async {
    if (_blockedProcessNames.isEmpty) return;
    final running = await _runningProcessNames();
    for (final blocked in _blockedProcessNames) {
      if (running.contains(blocked)) {
        final killed = await _killProcessByName(blocked);
        if (killed) _blockedController.add(blocked);
      }
    }
  }

  Future<Set<String>> _runningProcessNames() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
        final out = (result.stdout as String? ?? '');
        return out
            .split('\n')
            .map(
              (line) => line.split(',').firstOrNull?.replaceAll('"', '').trim(),
            )
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .toSet();
      } else {
        final result = await Process.run('ps', ['-eo', 'comm=']);
        final out = (result.stdout as String? ?? '');
        return out
            .split('\n')
            .map((line) => line.trim())
            .where((name) => name.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      return {};
    }
  }

  Future<bool> _killProcessByName(String name) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('taskkill', ['/IM', name, '/F', '/T']);
        return result.exitCode == 0;
      } else {
        final result = await Process.run('pkill', ['-x', name]);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
