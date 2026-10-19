import '../src/common/port_exception.dart';
import '../src/todoist/todoist_api.dart';

/// In-memory [TodoistApi] and [TodoistSecrets] for tests and the demo mode.
///
/// Knows the projects „Eingang“ (Inbox) and „Arbeit“. The token
/// [validToken] is accepted; every other one gives `permissionDenied`.
/// [failWith] makes all calls fail while it is set.
final class FakeTodoistApi implements TodoistApi, TodoistSecrets {
  /// Creates the fake with [projectRows] and open [tasks].
  FakeTodoistApi({
    List<TodoistProject>? projectRows,
    List<TodoistTask> tasks = const [],
    this.storedToken = validToken,
  }) : projectRows =
           projectRows ??
           const [
             TodoistProject(id: 'p-inbox', name: 'Eingang', inbox: true),
             TodoistProject(id: 'p-work', name: 'Arbeit'),
           ],
       open = [...tasks];

  /// The token the fake accepts.
  static const validToken = 'fake-todoist-token';

  /// Token returned by [token] (`null` = not set up).
  String? storedToken;

  /// Projects.
  final List<TodoistProject> projectRows;

  /// Open tasks.
  final List<TodoistTask> open;

  /// Completed tasks (kept for reopening).
  final Map<String, TodoistTask> done = {};

  /// Error thrown by every call, if set.
  PortException? failWith;

  /// Operations called, in order (no arguments).
  final List<String> calls = [];

  int _next = 1;

  @override
  Future<String?> token() async => storedToken;

  void _check(String token, String op) {
    calls.add(op);
    final f = failWith;
    if (f != null) throw f;
    if (token != validToken) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Todoist-Zugang abgelehnt: Token ungültig oder widerrufen',
      );
    }
  }

  PortException get _gone => const PortException(
    PortErrorKind.notFound,
    'Todoist: Aufgabe nicht gefunden',
  );

  @override
  Future<List<TodoistProject>> projects(String token) async {
    _check(token, 'projects');
    return [...projectRows];
  }

  @override
  Future<List<TodoistTask>> tasks(String token, {String? projectId}) async {
    _check(token, 'tasks');
    return [
      for (final t in open)
        if (projectId == null || t.projectId == projectId) t,
    ];
  }

  @override
  Future<TodoistTask> addTask(
    String token, {
    required String content,
    String? projectId,
    String? dueString,
    int? priority,
  }) async {
    _check(token, 'add');
    final task = TodoistTask(
      id: 't-${_next++}',
      content: content,
      projectId: projectId ?? projectRows.first.id,
      // Only ISO input is understood; the real service parses language.
      dueDate: dueString == null
          ? null
          : RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(dueString)?.group(0),
      dueTime: dueString == null
          ? null
          : RegExp(r'\d{2}:\d{2}$').firstMatch(dueString)?.group(0),
      priority: priority ?? 1,
    );
    open.add(task);
    return task;
  }

  @override
  Future<void> closeTask(String token, String id) async {
    _check(token, 'close');
    final i = open.indexWhere((t) => t.id == id);
    if (i < 0) throw _gone;
    done[id] = open.removeAt(i);
  }

  @override
  Future<void> reopenTask(String token, String id) async {
    _check(token, 'reopen');
    final t = done.remove(id);
    if (t == null) throw _gone;
    open.add(t);
  }

  @override
  Future<void> deleteTask(String token, String id) async {
    _check(token, 'delete');
    final before = open.length;
    open.removeWhere((t) => t.id == id);
    if (open.length == before) throw _gone;
  }
}
