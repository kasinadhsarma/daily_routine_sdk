import 'package:equatable/equatable.dart';

/// A platform app/process the user has chosen to make blockable.
///
/// [packageId] holds an Android package name (e.g. `com.instagram.android`)
/// on mobile, or a process/executable name (e.g. `chrome`, `discord.exe`)
/// on desktop.
class BlockedApp extends Equatable {
  const BlockedApp({
    required this.packageId,
    required this.displayName,
    this.isCurrentlyBlocked = false,
    this.iconBytesBase64,
  });

  final String packageId;
  final String displayName;
  final bool isCurrentlyBlocked;
  final String? iconBytesBase64;

  BlockedApp copyWith({bool? isCurrentlyBlocked}) => BlockedApp(
    packageId: packageId,
    displayName: displayName,
    isCurrentlyBlocked: isCurrentlyBlocked ?? this.isCurrentlyBlocked,
    iconBytesBase64: iconBytesBase64,
  );

  Map<String, dynamic> toJson() => {
    'packageId': packageId,
    'displayName': displayName,
    'isCurrentlyBlocked': isCurrentlyBlocked,
  };

  factory BlockedApp.fromJson(Map<String, dynamic> json) => BlockedApp(
    packageId: json['packageId'] as String,
    displayName: json['displayName'] as String,
    isCurrentlyBlocked: json['isCurrentlyBlocked'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [packageId, displayName, isCurrentlyBlocked];
}
