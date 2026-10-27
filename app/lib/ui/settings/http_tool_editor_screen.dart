import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart' show SecurityLevel;
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/http_tools.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'http_tool_editor/args_section.dart';
import 'http_tool_editor/auth_section.dart';
import 'http_tool_editor/placeholder_text_controller.dart';
import 'http_tool_editor/run_section.dart';
import 'http_tool_editor/source_section.dart';
import 'http_tool_editor/test_run_panel.dart';
import 'http_tool_editor/tool_section.dart';
import 'settings_page.dart';
import 'tool_level_field.dart';

export 'http_tool_editor/placeholder_text_controller.dart';
export 'http_tool_editor/test_run_panel.dart' show HttpTestResultView;

/// Editor of one HTTP tool (WP28): name (tool-name rule checked live),
/// description, method, URL template with highlighted placeholders,
/// headers, secret headers or bearer token (masked, only replaceable),
/// body template, arguments (list or own schema), level with suggestion
/// by method, „Ohne Nachfrage ausführen“, „sensibel“, home network, time
/// limit; test run and save/delete.
class HttpToolEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor for [definition], or for a new tool.
  const HttpToolEditorScreen({super.key, this.definition});

  /// The stored definition; `null` = new tool.
  final HttpToolDefinition? definition;

  @override
  ConsumerState<HttpToolEditorScreen> createState() => _EditorState();
}

class _EditorState extends ConsumerState<HttpToolEditorScreen> {
  late HttpToolDraft _draft;
  late final PlaceholderTextController _url;
  final Map<String, TextEditingController> _testArgs = {};
  final Set<Object> _replacing = {};
  List<String> _otherNames = const [];
  HttpToolTestResult? _result;
  String? _testError;
  bool _testing = false;
  bool _saving = false;

  /// The level the user picked here (`null` = default); written with the
  /// tool on save, so a tool that is never saved leaves no entry.
  SecurityLevel? _pickedLevel;
  bool _levelPicked = false;

  @override
  void initState() {
    super.initState();
    final d = widget.definition;
    final repository = ref.read(httpToolRepositoryProvider);
    _draft = d == null
        ? HttpToolDraft.empty(repository.newId())
        : HttpToolDraft.of(d);
    _url = PlaceholderTextController(
      text: _draft.url,
      known: () => _draft.argNames(),
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = ref.read(httpToolRepositoryProvider);
    final all = await repository.definitions();
    final d = widget.definition;
    Set<String> stored = const {};
    if (d != null) {
      stored = {
        for (final r in httpSecretRefs(d.auth))
          if (await repository.hasSecret(r)) r,
      };
    }
    if (!mounted) return;
    setState(() {
      _otherNames = [
        for (final o in all)
          if (o.id != _draft.id) o.name,
      ];
      if (d != null) {
        _draft.bearerStored = stored.contains(httpBearerRef(d.id));
        for (final h in _draft.secretHeaders) {
          h.stored = stored.contains(httpHeaderRef(d.id, h.name));
        }
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    for (final c in _testArgs.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _edit(void Function() change) => setState(() {
    change();
    _result = null;
    _testError = null;
  });

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final problem = draft.problem(_otherNames);
    final types = draft.argTypes();
    for (final name in types.keys) {
      _testArgs.putIfAbsent(name, TextEditingController.new);
    }
    return SettingsPage(
      title: draft.isNew
          ? context.l10n.httpEditorNewTool
          : context.l10n.httpEditorTool,
      children: [
        ToolSection(draft: draft, otherNames: _otherNames, onEdit: _edit),
        RequestSection(draft: draft, url: _url, onEdit: _edit),
        AuthSection(
          draft: draft,
          replacing: _replacing,
          onReplace: (owner) => setState(() => _replacing.add(owner)),
          onEdit: _edit,
        ),
        ArgsSection(draft: draft, onEdit: _edit),
        RunSection(draft: draft, onEdit: _edit, levelField: _levelField()),
        if (problem != null)
          Text(
            problem,
            key: const ValueKey('problem'),
            style: WText.caption.copyWith(color: WColors.error),
          ),
        TestRunPanel(
          argTypes: types,
          controllers: _testArgs,
          canTest: problem == null && !_testing,
          testing: _testing,
          onTest: () => unawaited(_test()),
          error: _testError,
          result: _result,
        ),
        PrimaryButton(
          context.l10n.save,
          onPressed: problem == null && !_saving
              ? () => unawaited(_save())
              : null,
        ),
        if (!draft.isNew)
          WideButton(
            context.l10n.delete,
            onPressed: () => unawaited(_delete()),
          ),
      ],
    );
  }

  String get _toolName => 'http__${_draft.name.trim()}';

  Widget? _levelField() {
    if (_draft.name.trim().isEmpty) return null;
    var prefs = ref.watch(toolPrefsProvider);
    final old = widget.definition?.toolName;
    // A renamed tool keeps its level (see [_saveLevel]).
    if (old != null) prefs = prefs.renamed(old, _toolName);
    return ToolLevelField(
      toolName: _toolName,
      risk: _draft.effectiveRisk,
      sensitive: _draft.sensitive,
      stored: _levelPicked ? _pickedLevel?.name : prefs.levelOf(_toolName),
      onChanged: (l) => setState(() {
        _levelPicked = true;
        _pickedLevel = l;
      }),
    );
  }

  /// Stores the level with the tool: a picked one under the (new) name,
  /// otherwise the level of the old name moves along with a rename.
  Future<void> _saveLevel() async {
    final notifier = ref.read(toolPrefsProvider.notifier);
    var prefs = ref.read(toolPrefsProvider);
    final old = widget.definition?.toolName;
    if (old != null && old != _toolName) prefs = prefs.renamed(old, _toolName);
    if (_levelPicked) prefs = prefs.withLevel(_toolName, _pickedLevel);
    await notifier.set(prefs);
  }

  Future<void> _test() async {
    final HttpToolDefinition definition;
    final args = <String, Object?>{};
    try {
      definition = _draft.toDefinition();
      for (final MapEntry(key: name, value: type)
          in _draft.argTypes().entries) {
        final v = parseHttpArg(_testArgs[name]?.text ?? '', type);
        if (v != null) args[name] = v;
      }
    } on FormatException catch (e) {
      setState(() => _testError = e.message);
      return;
    }
    final runner = ref.read(httpToolRunnerFactoryProvider)(
      PendingHttpToolSecrets(
        ref.read(httpToolSecretsProvider),
        _draft.secretChanges(),
      ),
    );
    setState(() {
      _testing = true;
      _testError = null;
      _result = null;
    });
    final result = await HttpToolTester(runner).run(definition, args);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  Future<void> _save() async {
    final HttpToolDefinition definition;
    try {
      definition = _draft.toDefinition();
    } on FormatException catch (e) {
      showHint(context, e.message);
      return;
    }
    final repository = ref.read(httpToolRepositoryProvider);
    final settings = ref.read(storageProvider).settings;
    final registered = {
      for (final i in ref.read(toolRegistryProvider).integrations) i.id,
    };
    setState(() => _saving = true);
    try {
      await enableHttpIntegrationIfNew(settings, registered, definition);
      await repository.save(definition, secretValues: _draft.secretChanges());
      await _saveLevel();
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showHint(context, stripHttpToolPrefix(e.message));
      }
      return;
    }
    SecretField.finishAutofill();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final repository = ref.read(httpToolRepositoryProvider);
    final ok = await confirm(
      context,
      title: context.l10n.httpEditorDeleteTitle,
      message: context.l10n.httpEditorDeleteBody(widget.definition!.name),
      yes: context.l10n.delete,
    );
    if (!ok) return;
    await repository.delete(_draft.id);
    final prefs = ref.read(toolPrefsProvider);
    await ref
        .read(toolPrefsProvider.notifier)
        .set(prefs.withLevel(widget.definition!.toolName, null));
    if (mounted) Navigator.of(context).pop();
  }
}
