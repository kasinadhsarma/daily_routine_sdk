import 'dart:async';
import 'dart:io';

import 'package:daily_routine_sdk/models/app_usage_event.dart';
import 'package:daily_routine_sdk/usage/app_usage_tracker_service.dart';

/// Desktop (Linux/Windows/macOS) implementation.
///
/// There is no cross-platform "focused window" API, so this shells out to
/// the OS's own tools every few seconds: `xprop`/`xdotool` on Linux (X11 —
/// including XWayland; a window running as a *native* Wayland client on a
/// Wayland-only session is invisible to these tools, a known ecosystem gap,
/// not something fixable from userspace), a small inline Win32 call via
/// PowerShell on Windows, and `osascript`/System Events on macOS (window
/// *titles* there require the user to have granted this app Accessibility
/// access — the frontmost app name alone does not).
///
/// A "session" is keyed on (app, window title) — so switching browser tabs
/// or files in an editor ends one session and starts another, same
/// granularity as the Chrome extension's per-page tracking.
class DesktopAppUsageTrackerService extends AppUsageTrackerService {
  DesktopAppUsageTrackerService();

  static void registerWith() {
    AppUsageTrackerService.instance = DesktopAppUsageTrackerService();
  }

  static const _pollInterval = Duration(seconds: 3);
  static const _minSessionMs = 2000;

  Timer? _pollTimer;
  final _controller = StreamController<AppUsageEvent>.broadcast();

  String? _currentApp;
  String? _currentTitle;
  DateTime? _currentStartedAt;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> startTracking() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  @override
  Future<void> stopTracking() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _flush();
  }

  @override
  Stream<AppUsageEvent> get events => _controller.stream;

  Future<void> _tick() async {
    final info = await _activeWindowInfo();
    if (info == null) return;

    if (info.appName != _currentApp || info.windowTitle != _currentTitle) {
      _flush();
      _currentApp = info.appName;
      _currentTitle = info.windowTitle;
      _currentStartedAt = DateTime.now();
    }
  }

  void _flush() {
    final app = _currentApp;
    final startedAt = _currentStartedAt;
    if (app == null || startedAt == null) return;
    _currentApp = null;

    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (durationMs < _minSessionMs) return;

    _controller.add(
      AppUsageEvent(
        packageName: app,
        appLabel: app,
        startedAt: startedAt,
        durationMs: durationMs,
        windowTitle: _currentTitle,
      ),
    );
  }

  Future<_WindowInfo?> _activeWindowInfo() async {
    try {
      if (Platform.isLinux) return await _linuxActiveWindow();
      if (Platform.isWindows) return await _windowsActiveWindow();
      if (Platform.isMacOS) return await _macosActiveWindow();
    } catch (_) {
      // Best-effort — missing tools, no permission yet, etc. Just skip
      // this tick rather than crash the polling loop.
    }
    return null;
  }

  Future<_WindowInfo?> _linuxActiveWindow() async {
    final activeIdResult = await Process.run('xprop', ['-root', '_NET_ACTIVE_WINDOW']);
    if (activeIdResult.exitCode != 0) return null;
    final idMatch = RegExp(
      r'#\s*(0x[0-9a-fA-F]+)',
    ).firstMatch(activeIdResult.stdout as String);
    final windowId = idMatch?.group(1);
    if (windowId == null) return null;

    final titleResult = await Process.run('xdotool', ['getwindowname', windowId]);
    final title = titleResult.exitCode == 0
        ? (titleResult.stdout as String).trim()
        : null;
    if (title == null || title.isEmpty) return null;

    String appName = title;
    final classResult = await Process.run('xprop', ['-id', windowId, 'WM_CLASS']);
    if (classResult.exitCode == 0) {
      final classMatch = RegExp(
        r'"[^"]*",\s*"([^"]+)"',
      ).firstMatch(classResult.stdout as String);
      if (classMatch != null) appName = classMatch.group(1)!;
    }

    return _WindowInfo(appName: appName, windowTitle: title);
  }

  Future<_WindowInfo?> _windowsActiveWindow() async {
    const script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class DrWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@
$hwnd = [DrWin32]::GetForegroundWindow()
$sb = New-Object System.Text.StringBuilder 512
[DrWin32]::GetWindowText($hwnd, $sb, 512) | Out-Null
$procId = 0
[DrWin32]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null
$proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
Write-Output "$($proc.ProcessName)|$($sb.ToString())"
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) return null;
    final line = (result.stdout as String).trim();
    final sep = line.indexOf('|');
    if (sep < 0) return null;
    final appName = line.substring(0, sep).trim();
    final title = line.substring(sep + 1).trim();
    if (appName.isEmpty || title.isEmpty) return null;
    return _WindowInfo(appName: appName, windowTitle: title);
  }

  Future<_WindowInfo?> _macosActiveWindow() async {
    final appResult = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to get name of first process whose frontmost is true',
    ]);
    if (appResult.exitCode != 0) return null;
    final appName = (appResult.stdout as String).trim();
    if (appName.isEmpty) return null;

    // Window title needs Accessibility permission granted to this app; if
    // it's not granted this just fails and we fall back to the app name.
    String title = appName;
    final titleResult = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to tell (first process whose frontmost is true) '
          'to get title of front window',
    ]);
    if (titleResult.exitCode == 0) {
      final raw = (titleResult.stdout as String).trim();
      if (raw.isNotEmpty) title = raw;
    }

    return _WindowInfo(appName: appName, windowTitle: title);
  }
}

class _WindowInfo {
  const _WindowInfo({required this.appName, required this.windowTitle});
  final String appName;
  final String windowTitle;
}
