/// Typed error contract every SDK service returns instead of a raw platform
/// exception, so app code never has to catch `FirebaseException`,
/// `PlatformException`, etc. directly.
sealed class AppError {
  const AppError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

class AuthError extends AppError {
  const AuthError(super.message, {this.code, super.cause, super.stackTrace});

  final String? code;
}

class DatabaseError extends AppError {
  const DatabaseError(super.message, {super.cause, super.stackTrace});
}

class PermissionError extends AppError {
  const PermissionError(super.message, {super.cause, super.stackTrace});
}

class UnknownError extends AppError {
  const UnknownError(super.message, {super.cause, super.stackTrace});
}
