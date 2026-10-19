import '../common/matching.dart';
import '../common/port_exception.dart';
import 'todoist_api.dart';

/// Hint appended to errors that pause the integration.
const todoistPausedHint =
    'Todoist-Tools sind pausiert. Neuen Token unter Einstellungen → '
    'Integrationen → Todoist eintragen.';

/// Hint appended to temporary errors (offline, timeout, 429, 5xx).
const todoistRetryHint = 'Bitte später erneut versuchen.';

/// Token handling and error state of the Todoist tools.
///
/// Every API call runs through [run]: the token comes from [TodoistSecrets]
/// (read per call, so a new token takes effect at once). A rejected token
/// (`permissionDenied`) or an unexpected answer (`failed`) is a lasting
/// failure: [onError] is called (the app: `ToolRegistry.reportError`, tools
/// paused) and the error is rethrown with [todoistPausedHint]. Temporary
/// failures (`unavailable`) only fail the call. Nothing is repeated
/// automatically. Messages never contain the token.
final class TodoistSession {
  /// Creates the session.
  TodoistSession(this.api, this.secrets, {this.onError, this.onRecovered});

  /// The API client.
  final TodoistApi api;

  /// Where the token lives.
  final TodoistSecrets secrets;

  /// Called with a German message when the integration must show „Fehler“.
  final void Function(String message)? onError;

  /// Called when a call succeeds after [onError].
  final void Function()? onRecovered;

  bool _failed = false;

  /// Whether the last failure paused the integration and no call has
  /// succeeded since.
  bool get failed => _failed;

  /// Error when no token is stored (setup, not a failure).
  static const notSetUp = PortException(
    PortErrorKind.permissionDenied,
    'Todoist ist nicht eingerichtet (Einstellungen → Integrationen → '
    'Todoist).',
  );

  /// Runs [op] with the stored token (see the class comment).
  Future<T> run<T>(Future<T> Function(String token) op) async {
    final token = await secrets.token();
    if (token == null || token.isEmpty) throw notSetUp;
    try {
      final result = await op(token);
      if (_failed) {
        _failed = false;
        onRecovered?.call();
      }
      return result;
    } on PortException catch (e) {
      switch (e.kind) {
        case PortErrorKind.unavailable:
          throw PortException(e.kind, '${e.message}. $todoistRetryHint');
        case PortErrorKind.permissionDenied || PortErrorKind.failed:
          _failed = true;
          onError?.call(e.message);
          throw PortException(e.kind, '${e.message}. $todoistPausedHint');
        default:
          rethrow;
      }
    }
  }

  /// Projects of the account.
  Future<List<TodoistProject>> projects() => run(api.projects);

  /// The project [query] names (fuzzy, like the lists integration), or the
  /// Inbox for `null`/blank. With [write], a whole-word match only is asked
  /// back. Throws `PortException(notFound|rejected)`.
  Future<TodoistProject> resolveProject(
    String? query, {
    required bool write,
  }) async {
    final projects = await this.projects();
    if (projects.isEmpty) {
      throw const PortException(
        PortErrorKind.notFound,
        'Im Todoist-Konto gibt es keine Projekte.',
      );
    }
    final names = projects.map((p) => p.name).join(', ');
    if (query == null || query.trim().isEmpty) {
      for (final p in projects) {
        if (p.inbox) return p;
      }
      if (projects.length == 1) return projects.single;
      throw PortException(
        PortErrorKind.rejected,
        'Welches Todoist-Projekt? Vorhanden: $names. Bitte nachfragen.',
      );
    }
    final m = bestMatches(query, projects, (p) => [p.name]);
    if (m.best.isEmpty) {
      throw PortException(
        PortErrorKind.notFound,
        'Kein Todoist-Projekt „$query“. Vorhanden: $names',
      );
    }
    if (m.best.length > 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Mehrdeutig: „$query“ passt zu '
        '${m.best.map((p) => p.name).join(', ')}. Bitte nachfragen, welches '
        'Todoist-Projekt gemeint ist.',
      );
    }
    if (write && m.score == 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Meintest du das Todoist-Projekt „${m.best.single.name}“? Bitte '
        'nachfragen.',
      );
    }
    return m.best.single;
  }
}
