import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/models/activity_event.dart';

/// Persists and reads back logged activity (browser tab sessions from the
/// Chrome extension, app-usage sessions from [AppUsageTrackerService]) —
/// all stored at `users/{uid}/activity`, shared across every client.
abstract class ActivityRepositoryService {
  Future<Result<void>> logAppUsage(String uid, AppUsageEvent event);

  /// Most recent activity, newest first. Only includes docs that carry a
  /// `startedAt` timestamp (mobile app sessions and Chrome page sessions;
  /// YouTube video docs from the extension track `lastWatchedAt` instead
  /// and won't appear in this feed yet).
  Stream<List<ActivityEvent>> watchRecentActivity(String uid, {int limit = 50});
}
