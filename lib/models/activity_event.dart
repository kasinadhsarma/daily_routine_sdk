import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A single logged activity — a browser tab session (from the Chrome
/// extension) or a mobile app-usage session (from [AppUsageTrackerService]),
/// read back from `users/{uid}/activity`.
class ActivityEvent extends Equatable {
  const ActivityEvent({
    required this.id,
    required this.source,
    required this.type,
    required this.title,
    this.domain,
    this.packageName,
    this.url,
    this.windowTitle,
    this.startedAt,
    this.durationMs,
  });

  final String id;
  final String source; // 'chrome' | 'android' | 'desktop'
  final String type; // 'page' | 'video' | 'app'
  final String title;
  final String? domain;
  final String? packageName;
  final String? url;

  /// Focused window title (desktop app sessions only) — the file open in
  /// an editor, the video playing, the browser tab, etc.
  final String? windowTitle;
  final DateTime? startedAt;
  final int? durationMs;

  Duration get duration => Duration(milliseconds: durationMs ?? 0);

  factory ActivityEvent.fromFirestore(String id, Map<String, dynamic> data) {
    final startedAtRaw = data['startedAt'];
    // Native `cloud_firestore` writes a real Timestamp; the Linux REST path
    // (see `RestActivityRepositoryService`) stores an ISO-8601 string
    // instead, same as every other REST-backed model in this SDK.
    final DateTime? startedAt = switch (startedAtRaw) {
      Timestamp t => t.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
    return ActivityEvent(
      id: id,
      source: data['source'] as String? ?? 'unknown',
      type: data['type'] as String? ?? 'unknown',
      title: data['title'] as String? ?? data['appLabel'] as String? ?? '',
      domain: data['domain'] as String?,
      packageName: data['packageName'] as String?,
      url: data['url'] as String?,
      windowTitle: data['windowTitle'] as String?,
      startedAt: startedAt,
      durationMs: (data['durationMs'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props =>
      [id, source, type, title, domain, packageName, url, windowTitle, startedAt, durationMs];
}
