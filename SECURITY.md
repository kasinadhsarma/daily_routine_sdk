# Security Policy

## Supported versions

This is a personal-use project. Only the latest release and `main` receive
security fixes.

## Reporting a vulnerability

Please **do not open a public GitHub issue** for security vulnerabilities.

Preferred: use GitHub's [private vulnerability reporting](https://github.com/kasinadhsarma/daily_routine_sdk/security/advisories/new)
("Security" tab → "Report a vulnerability") on this repo.

Alternatively, email **kasinadhsarma@gmail.com** with:

- A description of the vulnerability and its impact.
- Steps to reproduce (a minimal proof of concept, if you have one).
- Any suggested fix, if you have one.

You should get an acknowledgement within a few days. Please allow time to
investigate and ship a fix before any public disclosure.

## Scope notes

This package provides the data-access layer (`activity/`, `blocked_apps/`,
`routines/`) consumed by `daily_routine`; access control for that data is
enforced by that app's `firestore.rules`, not by anything in here. Reports
about this SDK are most useful when they concern:

- Every service method here that can fail returns a `Result<T>` rather than
  letting `FirebaseException`/`PlatformException` escape — a path where a
  caller can't tell a failure occurred (silently swallowed error) is a bug.
- The Android foreground services (`AppBlockerService`,
  `AppUsageTrackerService`) run with the host app's permissions — a way to
  trigger blocking/tracking enforcement without holding Usage Access, or to
  read another app's data through them, is in scope.
- The REST-backed implementations (`blocked_apps/implementations/rest_*`,
  `routines/implementations/rest_*`, `activity/implementations/rest_*`,
  `auth/implementations/rest_auth_service.dart`) used on Linux desktop —
  token handling, or a request that doesn't actually scope to the
  authenticated user's own `uid`, is exactly what this policy is for.
