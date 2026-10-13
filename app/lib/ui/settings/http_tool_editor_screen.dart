import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/http_tool_draft.dart';
import '../../di/http_tools.dart';
import '../../di/providers.dart';
import '../design/design.dart';
import 'http_tool_editor/args_section.dart';
import 'http_tool_editor/auth_section.dart';
import 'http_tool_editor/placeholder_text_controller.dart';
import 'http_tool_editor/run_section.dart';
import 'http_tool_editor/source_section.dart';
import 'http_tool_editor/test_run_panel.dart';
import 'http_tool_editor/tool_section.dart';
import 'settings_page.dart';

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
      title: draft.isNew ? 'Neues HTTP-Tool' : 'HTTP-Tool',
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
        RunSection(draft: draft, onEdit: _edit),
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
          'Speichern',
          onPressed: problem == null && !_saving
              ? () => unawaited(_save())
              : null,
        ),
        if (!draft.isNew)
          WideButton('Löschen', onPressed: () => unawaited(_delete())),
      ],
    );
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
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showHint(context, stripHttpToolPrefix(e.message));
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final repository = ref.read(httpToolRepositoryProvider);
    final ok = await confirm(
      context,
      title: 'HTTP-Tool löschen?',
      message:
          '„http__${widget.definition!.name}“ und seine gespeicherten '
          'Secrets werden gelöscht.',
      yes: 'Löschen',
    );
    if (!ok) return;
    await repository.delete(_draft.id);
    if (mounted) Navigator.of(context).pop();
  }
}
