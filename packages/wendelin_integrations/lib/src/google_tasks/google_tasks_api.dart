import 'package:meta/meta.dart';

/// Client of the Google Tasks API (`https://tasks.googleapis.com/tasks/v1`).
/// Stateless: the caller passes a valid OAuth access token.
///
/// Every method throws `PortException` only, never a parse or socket error:
/// - `permissionDenied`: token rejected or Tasks API not enabled (401/403),
/// - `notFound`: unknown list or task (404),
/// - `rejected`: Google refused the input (400),
/// - `unavailable`: unreachable, timeout, rate limit (429), server error,
/// - `failed`: unexpected answer.
///
/// Messages are German and short and never contain tokens, response bodies
/// or task titles.
abstract interface class GoogleTasksApi {
  /// All task lists of the account (all result pages).
  Future<List<GoogleTaskList>> taskLists(String accessToken);

  /// All open tasks of [listId] (all result pages).
  Future<List<GoogleTask>> tasks(String accessToken, String listId);

  /// Creates a task. [due] is a date; Google stores no time of day.
  Future<GoogleTask> addTask(
    String accessToken,
    String listId, {
    required String title,
    String? due,
  });

  /// Marks the task done (`completed`) or open again (`needsAction`).
  Future<void> setCompleted(
    String accessToken,
    String listId,
    String taskId, {
    required bool completed,
  });

  /// Deletes the task.
  Future<void> deleteTask(String accessToken, String listId, String taskId);
}

/// A Google task list (used as a list).
@immutable
final class GoogleTaskList {
  /// Creates a list.
  const GoogleTaskList({required this.id, required this.title});

  /// List id.
  final String id;

  /// Display name.
  final String title;

  @override
  bool operator ==(Object other) =>
      other is GoogleTaskList && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);

  @override
  String toString() => 'GoogleTaskList($title)';
}

/// A Google task.
@immutable
final class GoogleTask {
  /// Creates a task.
  const GoogleTask({
    required this.id,
    required this.listId,
    required this.title,
    this.due,
  });

  /// Task id.
  final String id;

  /// Id of the list the task is in.
  final String listId;

  /// Title.
  final String title;

  /// Due date `YYYY-MM-DD`, if any.
  final String? due;

  @override
  bool operator ==(Object other) =>
      other is GoogleTask &&
      other.id == id &&
      other.listId == listId &&
      other.title == title &&
      other.due == due;

  @override
  int get hashCode => Object.hash(id, listId, title, due);

  /// Never shows the title (logs).
  @override
  String toString() => 'GoogleTask(<verborgen>)';
}
