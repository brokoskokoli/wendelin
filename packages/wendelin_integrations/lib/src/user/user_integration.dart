import 'package:wendelin_core/wendelin_core.dart';

/// Kind of a user-defined integration; shown as badge in the list.
enum UserIntegrationKind {
  /// A configured MCP server (WP27).
  mcp('MCP'),

  /// Declarative HTTP tools (WP28).
  http('HTTP');

  const UserIntegrationKind(this.badge);

  /// Badge text in the integration list.
  final String badge;
}

/// A source of user-defined integrations (ADR 0012): MCP servers, HTTP
/// tools. Unlike the built-in ones (`IntegrationSpec`) their number and
/// tools change at runtime when the user adds, edits or deletes one.
///
/// [UserIntegrationSync] registers what [load] returns, follows [changes]
/// and calls [deleteSecrets] once an integration or some of its tools have
/// disappeared.
abstract interface class UserIntegrationSource {
  /// What this source provides.
  UserIntegrationKind get kind;

  /// The current integrations, built from the stored configuration. An
  /// unchanged integration must be returned as the *identical* object; a
  /// new object counts as changed and is registered again (new tools,
  /// new URL, …). Ids must not clash with other integrations.
  Future<List<Integration>> load();

  /// Emits when [load] would return something else.
  Stream<void> get changes;

  /// Follow-up cleanup: removes the secrets (token, header values, OAuth
  /// tokens) of what [removal] describes from the `SecretStore`, reading
  /// the secret references from [IntegrationRemoval.integration] (the
  /// removed version). The source deletes secrets itself when the user
  /// deletes something; this call only catches what was left behind and
  /// must tolerate secrets that are already gone (ADR 0012 §2).
  Future<void> deleteSecrets(IntegrationRemoval removal);
}

/// What disappeared from a user-defined integration: the whole
/// integration ([whole]) or some of its tools (e.g. one HTTP tool deleted).
final class IntegrationRemoval {
  /// Creates the description.
  const IntegrationRemoval({
    required this.integration,
    required this.toolNames,
    required this.whole,
  });

  /// The removed (or replaced) version of the integration.
  final Integration integration;

  /// Names of the tools that are gone. Tools that moved to another
  /// integration of the same source (e.g. `http` → `http_sensitive`) are
  /// not included.
  final Set<String> toolNames;

  /// Whether the integration itself was deleted (not only some tools).
  final bool whole;

  /// Integration id.
  String get id => integration.id;
}

/// Cleanup after a user-defined integration or some of its tools were
/// removed (settings, marks, …).
typedef IntegrationCleanup = Future<void> Function(IntegrationRemoval removal);
