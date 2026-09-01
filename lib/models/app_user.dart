import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  static const empty = AppUser(uid: '');

  bool get isEmpty => this == empty;
  bool get isNotEmpty => this != empty;

  @override
  List<Object?> get props => [uid, email, displayName, photoUrl];
}
