import 'package:daily_routine_sdk/error/app_error.dart';

/// Typed outcome of an SDK operation — success with a value, or a typed
/// [AppError]. Keeps raw platform exceptions from leaking past the SDK
/// boundary into app code.
sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(AppError error) = Failure<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  R fold<R>(
    R Function(T value) onSuccess,
    R Function(AppError error) onFailure,
  ) {
    final self = this;
    return switch (self) {
      Success<T>() => onSuccess(self.value),
      Failure<T>() => onFailure(self.error),
    };
  }
}

class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

class Failure<T> extends Result<T> {
  const Failure(this.error);

  final AppError error;
}
