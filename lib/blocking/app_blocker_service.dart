import 'package:daily_routine_sdk/blocking/implementations/method_channel_app_blocker_service.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface every platform implementation of the app blocker must
/// satisfy. On Android this is backed by a `MethodChannel` talking to a
/// Kotlin foreground service; on desktop it is implemented in pure Dart via
/// `dart:io` process polling (see `DesktopAppBlockerService`).
abstract class AppBlockerService extends PlatformInterface {
  AppBlockerService() : super(token: _token);

  static final Object _token = Object();

  static AppBlockerService _instance = MethodChannelAppBlockerService();

  static AppBlockerService get instance => _instance;

  static set instance(AppBlockerService instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether this platform needs an explicit OS-level permission grant
  /// before it can observe the foreground app (Android's Usage Access).
  /// Desktop platforms don't need this and should return `false`.
  Future<bool> isPermissionRequired() =>
      throw UnimplementedError('isPermissionRequired() has not been implemented.');

  Future<bool> hasPermission() =>
      throw UnimplementedError('hasPermission() has not been implemented.');

  /// Opens the OS settings screen where the user can grant the permission.
  Future<void> requestPermission() =>
      throw UnimplementedError('requestPermission() has not been implemented.');

  /// Best-effort list of apps/processes the user could choose to block.
  /// On Android this is installed launchable apps; on desktop it is the
  /// set of currently-running processes.
  Future<List<BlockedApp>> getBlockableTargets() =>
      throw UnimplementedError('getBlockableTargets() has not been implemented.');

  /// Starts enforcing a block on the given package/process identifiers.
  Future<void> startBlocking(List<String> packageIds) =>
      throw UnimplementedError('startBlocking() has not been implemented.');

  /// Stops all enforcement.
  Future<void> stopBlocking() =>
      throw UnimplementedError('stopBlocking() has not been implemented.');

  /// Emits the identifier of whatever was just blocked, so the UI can show
  /// a "Nice try" screen or similar.
  Stream<String> get onAppBlocked =>
      throw UnimplementedError('onAppBlocked has not been implemented.');
}
