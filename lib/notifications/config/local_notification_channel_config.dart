/// Android notification-channel settings (required on Android 8+) for a
/// [NotificationService] implementation. Never hardcoded inside the
/// implementation — supplied by the composing app.
class LocalNotificationChannelConfig {
  const LocalNotificationChannelConfig({
    required this.channelId,
    required this.channelName,
    this.channelDescription,
    this.androidIcon = '@mipmap/ic_launcher',
  });

  final String channelId;
  final String channelName;
  final String? channelDescription;

  /// Android drawable/mipmap resource name used for the status-bar icon.
  final String androidIcon;
}
