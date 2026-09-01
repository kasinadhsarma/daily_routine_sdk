# daily_routine_sdk

Shared SDK for Daily Routine clients: platform-abstraction services for
Auth, the Firestore data layer, local task reminders, and cross-platform
app/process blocking — mirroring the service-interface + implementation
pattern used by `beyond_hire_sdk`.

## Layout

- `error/` — `Result<T>` / `AppError` (and subtypes: `AuthError`,
  `DatabaseError`, `PermissionError`, `UnknownError`). Every service method
  that can fail returns a `Result`, so app code never catches
  `FirebaseException`/`PlatformException` directly.
- `models/` — `RoutineTask`, `BlockedApp`, `AppUser`, plus
  `formatMinuteOfDay`/`nowAsMinuteOfDay` time-of-day helpers.
- `auth/` — `AuthService` interface + `FirebaseAuthService`.
- `routines/` — `RoutineRepositoryService` interface +
  `FirestoreRoutineRepositoryService`. Data lives at
  `users/{uid}/tasks/{taskId}`.
- `blocked_apps/` — `BlockedAppsRepositoryService` interface +
  `FirestoreBlockedAppsRepositoryService`. Data lives at
  `users/{uid}/blockedApps/{packageId}`. This only syncs the user's
  *selection* across devices — live enforcement is `blocking/`.
- `blocking/` — `AppBlockerService`, a `PlatformInterface`-based facade with
  two implementations:
  - **Android** (`MethodChannelAppBlockerService`) — a Kotlin foreground
    service polls `UsageStatsManager` once a second for the current
    foreground app; if it's on the active blocklist, a full-screen
    `BlockScreenActivity` is brought to front and the user is bounced home.
    Requires the user to grant Usage Access
    (`android.permission.PACKAGE_USAGE_STATS`) once, via system settings —
    call `requestPermission()` to open it.
  - **Desktop** (Linux/Windows/macOS, `DesktopAppBlockerService`) — pure
    Dart, no native code. Polls the OS process list (`ps`/`tasklist`) every
    2 seconds and kills (`pkill`/`taskkill`) any process on the blocklist.
    This is a deterrent, not a sandbox.
  - **iOS is not implemented.** True app blocking on iOS requires Apple's
    Screen Time `FamilyControls`/`DeviceActivity` entitlement, which needs a
    paid Apple Developer account and a manual entitlement request/approval
    from Apple. `AppBlockerService` is ready for an iOS implementation to be
    registered later once you have that entitlement.
- `notifications/` — `NotificationService` interface +
  `LocalNotificationService` (`flutter_local_notifications` +
  `timezone`/`flutter_timezone`). Scoped to on-device task reminders only
  (no push) — call `scheduleTaskReminder(task)` whenever a task is
  created/edited, and it reschedules based on `RoutineTask.repeatRule`.

## Using it

```dart
import 'package:daily_routine_sdk/daily_routine_sdk.dart';

final auth = FirebaseAuthService();
final routines = FirestoreRoutineRepositoryService();
final blockedApps = FirestoreBlockedAppsRepositoryService();
final blocker = AppBlockerService.instance; // Android or desktop, auto-selected
final notifications = LocalNotificationService(
  config: const LocalNotificationChannelConfig(
    channelId: 'routine_reminders',
    channelName: 'Routine reminders',
  ),
)..initialize();
```

Consuming apps declare this package as a `path:` dependency
(`daily_routine_sdk: {path: ../daily_routine_sdk}`) and still add
`firebase_core`/`firebase_auth`/`cloud_firestore` themselves for
`Firebase.initializeApp`.
