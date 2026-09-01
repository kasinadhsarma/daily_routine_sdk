import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/blocked_app.dart';

/// Persists the user's chosen blocklist (which apps/processes are eligible
/// to be blocked during a routine session).
///
/// The *live* enforcement of blocking happens on-device via
/// [AppBlockerService]; this only syncs the user's selection across devices.
abstract class BlockedAppsRepositoryService {
  Stream<List<BlockedApp>> watchBlockedApps(String uid);

  Future<Result<void>> setBlockedApps(String uid, List<BlockedApp> apps);

  Future<Result<void>> removeBlockedApp(String uid, String packageId);
}
