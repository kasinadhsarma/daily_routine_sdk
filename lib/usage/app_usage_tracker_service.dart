import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/usage/implementations/method_channel_app_usage_tracker_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface every platform implementation of the app-usage tracker
/// must satisfy. On Android this is backed by a `MethodChannel` talking to
/// a Kotlin foreground service that polls `UsageStatsManager`; other
/// platforms currently report [isPermissionRequired] support as
/// unavailable rather than tracking anything.
abstract class AppUsageTrackerService extends PlatformInterface {
  AppUsageTrackerService() : super(token: _token);

  static final Object _token = Object();

  static AppUsageTrackerService _instance = MethodChannelAppUsageTrackerService();

  static AppUsageTrackerService get instance => _instance;

  static set instance(AppUsageTrackerService instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether this platform can track app usage at all.
  Future<bool> isSupported() =>
      throw UnimplementedError('isSupported() has not been implemented.');

  Future<bool> hasPermission() =>
      throw UnimplementedError('hasPermission() has not been implemented.');

  /// Opens the OS settings screen where the user can grant the permission.
  Future<void> requestPermission() =>
      throw UnimplementedError('requestPermission() has not been implemented.');

  /// Starts the foreground service that observes app-switch sessions.
  Future<void> startTracking() =>
      throw UnimplementedError('startTracking() has not been implemented.');

  Future<void> stopTracking() =>
      throw UnimplementedError('stopTracking() has not been implemented.');

  /// Emits one event per completed foreground-app session while tracking
  /// is running and the Flutter engine is alive.
  Stream<AppUsageEvent> get events =>
      throw UnimplementedError('events has not been implemented.');
}
