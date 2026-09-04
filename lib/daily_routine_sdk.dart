/// Shared SDK (Auth, Firestore data layer, local reminders, and
/// cross-platform app/process blocking) for Daily Routine clients.
library;

export 'activity/activity_repository_service.dart';
export 'activity/implementations/firestore_activity_repository_service.dart';

export 'auth/auth_service.dart';
export 'auth/implementations/firebase_auth_service.dart';

export 'blocked_apps/blocked_apps_repository_service.dart';
export 'blocked_apps/implementations/firestore_blocked_apps_repository_service.dart';

export 'blocking/app_blocker_service.dart';
export 'blocking/implementations/desktop_app_blocker_service.dart'
    show DesktopAppBlockerService;
export 'blocking/implementations/method_channel_app_blocker_service.dart';

export 'config/rest_firebase_config.dart';

export 'error/app_error.dart';
export 'error/result.dart';

export 'models/activity_event.dart';
export 'models/activity_summary.dart';
export 'models/app_usage_event.dart';
export 'models/app_user.dart';
export 'models/blocked_app.dart';
export 'models/routine_task.dart';
export 'models/time_of_day_x.dart';

export 'notifications/config/local_notification_channel_config.dart';
export 'notifications/implementations/local_notification_service.dart';
export 'notifications/notification_service.dart';

export 'routines/implementations/firestore_routine_repository_service.dart';
export 'routines/routine_repository_service.dart';

export 'usage/app_usage_tracker_service.dart';
export 'usage/implementations/desktop_app_usage_tracker_service.dart';
export 'usage/implementations/method_channel_app_usage_tracker_service.dart';
