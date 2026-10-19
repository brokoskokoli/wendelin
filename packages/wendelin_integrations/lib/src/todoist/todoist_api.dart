import 'package:meta/meta.dart';

/// Client of the Todoist API v1 (`https://api.todoist.com/api/v1`) with the
/// user's personal API token. Stateless.
///
/// Every method throws `PortException` only, never a parse or socket error:
/// - `permissionDenied`: token rejected (HTTP 401/403),
/// - `notFound`: unknown task or project (HTTP 404),
/// - `rejected`: Todoist refused the input (HTTP 400, e.g. a due date it
///   cannot understand),
/// - `unavailable`: unreachable, timeout, rate limit (429), server error,
/// - `failed`: unexpected answer (HTML instead of JSON, missing fields).
///
/// Messages are German and short and never contain the token, the response
/// body or task titles. Must pass `todoistApiContract`.
abstract interface class TodoistApi {
  /// All projects of the account (all result pages).
  Future<List<TodoistProject>> projects(String token);

  /// All open tasks, optionally of one project (all result pages).
  Future<List<TodoistTask>> tasks(String token, {String? projectId});

  /// Creates a task. [dueString] is Todoist's natural language
  /// („tomorrow 9am“, „every monday“); [priority] 1 (normal) to 4 (urgent).
  Future<TodoistTask> addTask(
    String token, {
    required String content,
    String? projectId,
    String? dueString,
    int? priority,
  });

  /// Completes the task (a recurring task moves to its next date).
  Future<void> closeTask(String token, String id);

  /// Reopens a completed task.
  Future<void> reopenTask(String token, String id);

  /// Deletes the task.
  Future<void> deleteTask(String token, String id);
}

/// Where the Todoist token lives (app: `SecretStore`). Never SQLite,
/// settings JSON, logs or exports.
abstract interface class TodoistSecrets {
  /// The personal API token, or `null` if Todoist is not set up.
  Future<String?> token();
}

/// A Todoist project (used as a list).
@immutable
final class TodoistProject {
  /// Creates a project.
  const TodoistProject({
    required this.id,
    required this.name,
    this.inbox = false,
  });

  /// Project id.
  final String id;

  /// Display name.
  final String name;

  /// Whether this is the account's Inbox (default for new tasks).
  final bool inbox;

  @override
  bool operator ==(Object other) =>
      other is TodoistProject &&
      other.id == id &&
      other.name == name &&
      other.inbox == inbox;

  @override
  int get hashCode => Object.hash(id, name, inbox);

  @override
  String toString() => 'TodoistProject($name)';
}

/// A Todoist task.
@immutable
final class TodoistTask {
  /// Creates a task.
  const TodoistTask({
    required this.id,
    required this.content,
    required this.projectId,
    this.dueDate,
    this.dueTime,
    this.priority = 1,
    this.recurring = false,
  });

  /// Task id.
  final String id;

  /// Title (`content`).
  final String content;

  /// Id of the project the task is in.
  final String projectId;

  /// Due date `YYYY-MM-DD`, if any.
  final String? dueDate;

  /// Due time `HH:MM` (floating: wall-clock time of the user), if any.
  final String? dueTime;

  /// Todoist priority 1 (normal) to 4 (urgent).
  final int priority;

  /// Whether the task repeats.
  final bool recurring;

  @override
  bool operator ==(Object other) =>
      other is TodoistTask &&
      other.id == id &&
      other.content == content &&
      other.projectId == projectId &&
      other.dueDate == dueDate &&
      other.dueTime == dueTime &&
      other.priority == priority &&
      other.recurring == recurring;

  @override
  int get hashCode => Object.hash(
    id,
    content,
    projectId,
    dueDate,
    dueTime,
    priority,
    recurring,
  );

  /// Never shows the title (logs).
  @override
  String toString() => 'TodoistTask(<verborgen>)';
}
