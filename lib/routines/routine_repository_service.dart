import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';

/// CRUD + realtime access to a user's routine tasks.
abstract class RoutineRepositoryService {
  Stream<List<RoutineTask>> watchTasks(String uid);

  Future<Result<void>> upsertTask(String uid, RoutineTask task);

  Future<Result<void>> deleteTask(String uid, String taskId);

  Future<Result<void>> setTaskCompleted(
    String uid,
    String taskId, {
    required bool isCompleted,
  });
}
