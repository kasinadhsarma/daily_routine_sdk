import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';

/// Platform-abstraction boundary for local task reminders. This app has no
/// server sending pushes, so unlike a general-purpose SDK notification
/// service this is scoped to on-device scheduled reminders only.
abstract class NotificationService {
  /// Registers notification channels/callbacks. Call once at startup,
  /// before [requestPermission] or scheduling anything.
  Future<void> initialize();

  Future<Result<bool>> requestPermission();

  /// Schedules (or reschedules, replacing any existing reminder for the
  /// same task) a local reminder for [task] according to its
  /// `startMinuteOfDay` and `repeatRule`. No-ops if
  /// `task.reminderEnabled` is `false`.
  Future<void> scheduleTaskReminder(RoutineTask task);

  Future<void> cancelReminder(String taskId);

  Future<void> cancelAllReminders();
}
