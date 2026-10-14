import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../user/user_integration.dart';
import 'http_tool_definition.dart';
import 'http_tool_repository.dart';
import 'http_tool_runner.dart';
import 'http_tools_integration.dart';

/// [UserIntegrationSource] of the HTTP tools (ADR 0011 §6, ADR 0012): the
/// integrations `http` and `http_sensitive` built from the
/// [HttpToolRepository]. An integration is only offered while it has
/// tools; an unchanged one is returned as the identical object.
final class HttpToolSource implements UserIntegrationSource {
  /// Creates the source.
  HttpToolSource(this.repository, this.runner);

  /// The stored definitions.
  final HttpToolRepository repository;

  /// Executes the calls.
  final HttpToolRunner runner;

  final Map<bool, (List<HttpToolDefinition>, HttpToolsIntegration)> _built = {};

  @override
  UserIntegrationKind get kind => UserIntegrationKind.http;

  @override
  Stream<void> get changes => repository.changes;

  @override
  Future<List<Integration>> load() async {
    final all = await repository.definitions();
    final out = <Integration>[];
    for (final sensitive in [false, true]) {
      final defs = [
        for (final d in all)
          if (d.enabled && d.sensitive == sensitive) d,
      ];
      if (defs.isEmpty) {
        _built.remove(sensitive);
        continue;
      }
      final previous = _built[sensitive];
      if (previous != null &&
          const ListEquality<HttpToolDefinition>().equals(previous.$1, defs)) {
        out.add(previous.$2);
        continue;
      }
      final integration = HttpToolsIntegration(
        definitions: defs,
        runner: runner,
        sensitive: sensitive,
      );
      _built[sensitive] = (defs, integration);
      out.add(integration);
    }
    return out;
  }

  @override
  Future<void> deleteSecrets(IntegrationRemoval removal) async {
    final integration = unwrapHttpTools(removal.integration);
    if (integration == null) return;
    for (final d in integration.definitions) {
      if (removal.toolNames.contains(d.toolName)) {
        await repository.deleteSecretsOfRemoved(d.id);
      }
    }
  }
}

/// [integration] as [HttpToolsIntegration], if it is one.
HttpToolsIntegration? unwrapHttpTools(Integration integration) =>
    switch (integration) {
      final HttpToolsIntegration h => h,
      _ => null,
    };
