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
    this.startedAt,
    this.durationMs,
  });

  final String id;
  final String source; // 'chrome' | 'android'
  final String type; // 'page' | 'video' | 'app'
  final String title;
  final String? domain;
  final String? packageName;
  final String? url;
  final DateTime? startedAt;
  final int? durationMs;

  Duration get duration => Duration(milliseconds: durationMs ?? 0);

  factory ActivityEvent.fromFirestore(String id, Map<String, dynamic> data) {
    final startedAtRaw = data['startedAt'];
    return ActivityEvent(
      id: id,
      source: data['source'] as String? ?? 'unknown',
      type: data['type'] as String? ?? 'unknown',
      title: data['title'] as String? ?? data['appLabel'] as String? ?? '',
      domain: data['domain'] as String?,
      packageName: data['packageName'] as String?,
      url: data['url'] as String?,
      startedAt: startedAtRaw is Timestamp ? startedAtRaw.toDate() : null,
      durationMs: (data['durationMs'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [id, source, type, title, domain, packageName, url, startedAt, durationMs];
}
