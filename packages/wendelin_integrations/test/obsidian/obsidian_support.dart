import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

/// Test setup: fake vault, fake index, integration.
final class Obs {
  Obs({
    Map<String, String>? files,
    this.settings = const ObsidianSettings(vaultName: 'Mein Vault'),
    bool withOpener = true,
    NoteIndexer Function(VaultPort, NoteIndexPort)? indexer,
  }) : vault = FakeVaultPort(files: files) {
    integration = ObsidianIntegration(
      vault,
      index,
      settings: () => settings,
      openUri: withOpener ? (u) async => opened.add(u) : null,
      indexer: indexer?.call(vault, index),
    );
  }

  final FakeVaultPort vault;
  final FakeNoteIndex index = FakeNoteIndex();
  ObsidianSettings settings;
  final List<Uri> opened = [];
  late final ObsidianIntegration integration;

  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == 'obsidian__$name');

  /// Executes [name]; `replace_section` first prepares its confirmation
  /// like the runtime does (unless [prepare] is false).
  Future<ToolOutcome> call(
    String name,
    Map<String, Object?> args, {
    ToolContext? context,
    bool prepare = true,
  }) async {
    final t = tool(name);
    if (prepare && name == 'replace_section') {
      await t.confirmationText(args, context ?? ctx());
    }
    return t.execute(args, context ?? ctx());
  }

  /// Calls and expects success.
  Future<ToolOutcome> ok(
    String name,
    Map<String, Object?> args, {
    ToolContext? context,
  }) async {
    final o = await call(name, args, context: context);
    expect(o.isError, isFalse, reason: o.text);
    return o;
  }

  String file(String path) => vault.files[path]!;
}
