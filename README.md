# daily_routine_sdk

[![CI](https://github.com/kasinadhsarma/daily_routine_sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/kasinadhsarma/daily_routine_sdk/actions/workflows/ci.yml)
[![Release](https://github.com/kasinadhsarma/daily_routine_sdk/actions/workflows/release.yml/badge.svg)](https://github.com/kasinadhsarma/daily_routine_sdk/actions/workflows/release.yml)

Shared SDK for Daily Routine clients: platform-abstraction services for
Auth, the Firestore data layer, local task reminders, cross-platform
app/process blocking, and app-usage/activity tracking — mirroring the
service-interface + implementation pattern used by `beyond_hire_sdk`.

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
- `usage/` — `AppUsageTrackerService`, a `PlatformInterface`-based facade
  for logging foreground-app sessions, with two implementations:
  - **Android** (`MethodChannelAppUsageTrackerService`) — the same
    `UsageStatsManager`-polling foreground service as `blocking/`, but
    logging every session instead of enforcing a blocklist. No window
    titles (Android's usage API doesn't expose them).
  - **Desktop** (Linux/Windows/macOS, `DesktopAppUsageTrackerService`) —
    polls the OS's focused-window title every few seconds (`xprop`/
    `xdotool` on Linux/XWayland, a Win32 call via PowerShell on Windows,
    `osascript`/System Events on macOS) and keys a session on (app, window
    title) — so switching files/tabs starts a new session, same
    granularity as the Chrome extension. A native-Wayland window (no
    XWayland) is invisible to this on Linux; macOS window titles need
    Accessibility permission granted or it falls back to just the app name.
    Both best-effort, same spirit as `blocking/`'s desktop implementation.
- `activity/` — `ActivityRepositoryService` interface +
  `FirestoreActivityRepositoryService`, writing/reading
  `users/{uid}/activity/{eventId}` — the same collection the
  [Chrome extension](https://github.com/kasinadhsarma/daily-routine-activity-tracker)
  writes browser tab/video sessions into, so `watchRecentActivity` returns
  a combined feed across every device.

## Using it

```dart
import 'package:daily_routine_sdk/daily_routine_sdk.dart';

final auth = FirebaseAuthService();
final routines = FirestoreRoutineRepositoryService();
final blockedApps = FirestoreBlockedAppsRepositoryService();
final blocker = AppBlockerService.instance; // Android or desktop, auto-selected
final usageTracker = AppUsageTrackerService.instance; // ditto
final activity = FirestoreActivityRepositoryService();
final notifications = LocalNotificationService(
  config: const LocalNotificationChannelConfig(
    channelId: 'routine_reminders',
    channelName: 'Routine reminders',
  ),
)..initialize();
```

Consuming apps declare this as a git dependency and still add
`firebase_core`/`firebase_auth`/`cloud_firestore` themselves for
`Firebase.initializeApp`:

```yaml
daily_routine_sdk:
  git:
    url: https://github.com/kasinadhsarma/daily_routine_sdk.git # or git@github.com:... over SSH
    ref: main # or a released tag, e.g. v0.1.0
```

This repo is private, so CI in `daily_routine` fetches it over SSH via a
read-only deploy key rather than the HTTPS URL above — see that repo's
`.github/workflows/`. For local development, a gitignored
`pubspec_overrides.yaml` with `{daily_routine_sdk: {path: ../daily_routine_sdk}}`
is the easiest way to pick up unpushed SDK edits without a commit+push each
time.

## CI/CD & releases

Every push/PR runs `flutter analyze` + `flutter test`
(`.github/workflows/ci.yml`). This package has no pub.dev publish step
(`publish_to: 'none'`), so a "release" here is just a tagged, CI-checked
commit that `daily_routine`'s `pubspec.yaml` (or anyone else's) can pin to
via `ref: vX.Y.Z` instead of floating on `main`.

To cut one: bump `version:` in `pubspec.yaml`, merge to `main`, then

```bash
git tag v0.2.0 && git push origin v0.2.0
```

which publishes a [GitHub Release](https://github.com/kasinadhsarma/daily_routine_sdk/releases)
with auto-generated notes (`.github/workflows/release.yml`).

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.
