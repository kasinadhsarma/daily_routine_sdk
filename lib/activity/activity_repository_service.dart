import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/models/activity_event.dart';
import 'package:daily_routine_sdk/models/activity_summary.dart';

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

  /// Every raw event still stored, oldest first — used only for the
  /// once-daily rollup pass ([ActivityRolloverService]), never polled. On a
  /// healthy install (rollover running daily) this is a small, bounded
  /// read; it's only expensive the first time it runs against a backlog
  /// that predates rollover existing at all.
  Future<Result<List<ActivityEvent>>> fetchAllEvents(String uid);

  /// Permanently deletes the given raw event ids — called by
  /// [ActivityRolloverService] once their day has been folded into an
  /// [ActivitySummary].
  Future<Result<void>> deleteEvents(String uid, List<String> eventIds);

  /// Writes (or overwrites) one day's pre-aggregated summary at
  /// `users/{uid}/activitySummaries/{summary.date}`.
  Future<Result<void>> saveDailySummary(String uid, ActivitySummary summary);

  /// Reads back a specific day's summary, or `null` if that day was never
  /// rolled up (e.g. today, or before rollover existed).
  Future<Result<ActivitySummary?>> getDailySummary(String uid, String date);

  /// The `yyyy-MM-dd` rollover last completed through, or `null` if it's
  /// never run — a single small doc read/write, shared across every device
  /// signed into this account, so rollover runs about once a day
  /// system-wide rather than once per device.
  Future<Result<String?>> getLastRolloverDate(String uid);
  Future<Result<void>> setLastRolloverDate(String uid, String date);
}
