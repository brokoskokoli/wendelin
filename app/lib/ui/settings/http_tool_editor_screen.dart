import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/http_tool_draft.dart';
import '../../di/http_tools.dart';
import '../../di/providers.dart';
import '../design/design.dart';
import 'settings_page.dart';

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
    return SettingsPage(
      title: draft.isNew ? 'Neues HTTP-Tool' : 'HTTP-Tool',
      children: [
        _toolSection(draft),
        _requestSection(draft),
        _authSection(draft),
        _argsSection(draft),
        _runSection(draft),
        if (problem != null)
          Text(
            problem,
            key: const ValueKey('problem'),
            style: WText.caption.copyWith(color: WColors.error),
          ),
        _testSection(draft, problem),
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

  Widget _toolSection(HttpToolDraft d) => SettingsSection(
    title: 'Tool',
    children: [
      _Field(
        child: TextFormField(
          key: const ValueKey('name'),
          initialValue: d.name,
          style: WText.mono,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Name',
            prefixText: 'http__',
            errorText: d.name.isEmpty ? null : d.nameError(_otherNames),
          ),
          onChanged: (v) => _edit(() => d.name = v),
        ),
      ),
      _Field(
        child: TextFormField(
          key: const ValueKey('description'),
          initialValue: d.description,
          style: WText.body,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Beschreibung fürs Modell',
            helperText: 'Wann und wofür das Modell das Tool nutzen soll',
          ),
          onChanged: (v) => _edit(() => d.description = v),
        ),
      ),
    ],
  );

  Widget _requestSection(HttpToolDraft d) => SettingsSection(
    title: 'Anfrage',
    children: [
      _Field(
        child: Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final m in HttpMethod.values)
              ChoiceChip(
                label: Text(m.verb),
                selected: d.method == m,
                onSelected: (_) => _edit(() => d.setMethod(m)),
              ),
          ],
        ),
      ),
      _Field(
        child: TextField(
          key: const ValueKey('url'),
          controller: _url,
          style: WText.mono,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'URL-Vorlage',
            helperText:
                'Platzhalter wie {entity} nur in Pfad und Query, Host fest',
            helperMaxLines: 2,
          ),
          onChanged: (v) => _edit(() => d.url = v),
        ),
      ),
      for (final (i, h) in d.headers.indexed)
        _Field(
          key: ObjectKey(h),
          child: Row(
            spacing: WSpace.s,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('headerName$i'),
                  initialValue: h.name,
                  style: WText.mono,
                  decoration: const InputDecoration(labelText: 'Header'),
                  onChanged: (v) => _edit(() => h.name = v),
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('headerValue$i'),
                  initialValue: h.value,
                  style: WText.mono,
                  decoration: const InputDecoration(labelText: 'Wert'),
                  onChanged: (v) => _edit(() => h.value = v),
                ),
              ),
              WIconButton(
                icon: WIcons.close,
                tooltip: 'Header entfernen',
                iconSize: WSize.iconSmall,
                onPressed: () => _edit(() => d.headers.remove(h)),
              ),
            ],
          ),
        ),
      SettingsRow(
        title: '+ Header',
        detail: 'Nicht geheim; Tokens gehören in die Anmeldung',
        onTap: () => _edit(() => d.headers.add(HttpHeaderDraft())),
      ),
      if (d.method.allowsBody) ...[
        _Field(
          child: Wrap(
            spacing: WSpace.s,
            children: [
              for (final (f, label) in [
                (HttpBodyFormat.json, 'JSON'),
                (HttpBodyFormat.form, 'Formular'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: d.bodyFormat == f,
                  onSelected: (_) => _edit(() => d.bodyFormat = f),
                ),
            ],
          ),
        ),
        _Field(
          child: TextFormField(
            key: const ValueKey('body'),
            initialValue: d.body,
            style: WText.mono,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Body-Vorlage (JSON)',
              helperText: '"{name}" wird typgerecht ersetzt; leer = kein Body',
            ),
            onChanged: (v) => _edit(() => d.body = v),
          ),
        ),
      ],
    ],
  );

  Widget _authSection(HttpToolDraft d) => SettingsSection(
    title: 'Anmeldung',
    children: [
      _Field(
        child: Wrap(
          spacing: WSpace.s,
          children: [
            for (final kind in HttpAuthKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: d.auth == kind,
                onSelected: (_) => _edit(() => d.auth = kind),
              ),
          ],
        ),
      ),
      if (d.auth == HttpAuthKind.bearer)
        _secretRow(
          owner: d,
          label: 'Bearer-Token',
          stored: d.bearerStored,
          onChanged: (v) => d.bearerNew = v,
        ),
      if (d.auth == HttpAuthKind.headers) ...[
        for (final (i, h) in d.secretHeaders.indexed)
          Column(
            key: ObjectKey(h),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (h.stored)
                SettingsRow(
                  title: h.name,
                  mono: true,
                  trailing: WIconButton(
                    icon: WIcons.close,
                    tooltip: 'Geheimen Header entfernen',
                    iconSize: WSize.iconSmall,
                    onPressed: () => _edit(() => d.secretHeaders.remove(h)),
                  ),
                )
              else
                _Field(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('secretHeaderName$i'),
                          initialValue: h.name,
                          style: WText.mono,
                          decoration: const InputDecoration(
                            labelText: 'Geheimer Header, z. B. X-Api-Key',
                          ),
                          onChanged: (v) => _edit(() => h.name = v),
                        ),
                      ),
                      WIconButton(
                        icon: WIcons.close,
                        tooltip: 'Geheimen Header entfernen',
                        iconSize: WSize.iconSmall,
                        onPressed: () => _edit(() => d.secretHeaders.remove(h)),
                      ),
                    ],
                  ),
                ),
              _secretRow(
                owner: h,
                label: 'Wert',
                stored: h.stored,
                onChanged: (v) => h.newValue = v,
                fieldKey: ValueKey('secretHeaderValue$i'),
              ),
            ],
          ),
        SettingsRow(
          title: '+ Geheimer Header',
          onTap: () =>
              _edit(() => d.secretHeaders.add(HttpSecretHeaderDraft())),
        ),
      ],
    ],
  );

  /// A secret value: stored ones are masked and can only be replaced.
  Widget _secretRow({
    required Object owner,
    required String label,
    required bool stored,
    required void Function(String value) onChanged,
    Key fieldKey = const ValueKey('secret'),
  }) {
    if (stored && !_replacing.contains(owner)) {
      return SettingsRow(
        title: label,
        detail: '$redactedSecret gespeichert',
        trailing: TextButton(
          onPressed: () => setState(() => _replacing.add(owner)),
          child: const Text('Ersetzen'),
        ),
      );
    }
    return _Field(
      child: AutofillGroup(
        child: SecretField(
          key: fieldKey,
          label: label,
          mono: true,
          helperText: stored ? 'Leer lassen behält den gespeicherten' : null,
          onChanged: (v) => _edit(() => onChanged(v)),
        ),
      ),
    );
  }

  Widget _argsSection(HttpToolDraft d) => SettingsSection(
    title: 'Argumente',
    children: [
      SettingsRow(
        title: 'Eigenes JSON-Schema',
        detail: 'Statt der einfachen Liste',
        trailing: WSwitch(
          value: d.rawSchema,
          semanticLabel: 'Eigenes JSON-Schema',
          onChanged: (on) => _edit(() {
            if (on) {
              try {
                d.schemaText = _pretty(d.schema());
              } on FormatException {
                // Die Liste ist noch unvollständig: Text bleibt.
              }
            }
            d.rawSchema = on;
          }),
        ),
      ),
      if (d.rawSchema)
        _Field(
          child: TextFormField(
            key: const ValueKey('schema'),
            initialValue: d.schemaText,
            style: WText.mono,
            minLines: 4,
            maxLines: 14,
            decoration: const InputDecoration(labelText: 'JSON-Schema'),
            onChanged: (v) => _edit(() => d.schemaText = v),
          ),
        )
      else ...[
        for (final (i, a) in d.args.indexed)
          _Field(
            key: ObjectKey(a),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  spacing: WSpace.s,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('argName$i'),
                        initialValue: a.name,
                        style: WText.mono,
                        decoration: const InputDecoration(labelText: 'Name'),
                        onChanged: (v) => _edit(() => a.name = v),
                      ),
                    ),
                    WIconButton(
                      icon: WIcons.close,
                      tooltip: 'Argument entfernen',
                      iconSize: WSize.iconSmall,
                      onPressed: () => _edit(() => d.args.remove(a)),
                    ),
                  ],
                ),
                Wrap(
                  spacing: WSpace.s,
                  children: [
                    for (final t in httpArgTypes)
                      ChoiceChip(
                        key: ValueKey('argType$i-$t'),
                        label: Text(t),
                        selected: a.type == t,
                        onSelected: (_) => _edit(() => a.type = t),
                      ),
                  ],
                ),
                TextFormField(
                  key: ValueKey('argDescription$i'),
                  initialValue: a.description,
                  style: WText.body,
                  decoration: const InputDecoration(labelText: 'Beschreibung'),
                  onChanged: (v) => _edit(() => a.description = v),
                ),
                Row(
                  children: [
                    Expanded(child: Text('Pflicht', style: WText.detail)),
                    WSwitch(
                      value: a.required,
                      semanticLabel: 'Pflicht ${a.name}',
                      onChanged: (on) => _edit(() => a.required = on),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SettingsRow(
          title: '+ Argument',
          onTap: () => _edit(() => d.args.add(HttpArgDraft())),
        ),
      ],
    ],
  );

  Widget _runSection(HttpToolDraft d) => SettingsSection(
    title: 'Ausführung',
    children: [
      _Field(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WSpace.s,
          children: [
            Text(
              'Stufe (Vorschlag für ${d.method.verb}: '
              '${d.method.suggestedRisk.name})',
              style: WText.detail,
            ),
            Wrap(
              spacing: WSpace.s,
              children: [
                for (final r in d.riskChoices)
                  ChoiceChip(
                    label: Text(r.name),
                    selected: d.risk == r,
                    onSelected: (_) => _edit(() => d.risk = r),
                  ),
              ],
            ),
          ],
        ),
      ),
      SettingsRow(
        title: 'Ohne Nachfrage ausführen (kein Rückgängig)',
        detail: d.autoRunAvailable
            ? 'Sonst fragt Wendelin vor jedem Aufruf nach'
            : 'Nur bei POST/PUT/PATCH mit Stufe write',
        trailing: WSwitch(
          value: d.autoRun && d.autoRunAvailable,
          semanticLabel: 'Ohne Nachfrage ausführen',
          onChanged: d.autoRunAvailable
              ? (on) => _edit(() => d.autoRun = on)
              : null,
        ),
      ),
      SettingsRow(
        title: 'Sensibel',
        detail: 'Nur an Provider ab der Stufe für sensible Integrationen',
        trailing: WSwitch(
          value: d.sensitive,
          semanticLabel: 'Sensibel',
          onChanged: (on) => _edit(() => d.sensitive = on),
        ),
      ),
      SettingsRow(
        title: 'Heimnetz-Ziel',
        detail: 'Darf auf private Adressen zeigen, dann auch http',
        trailing: WSwitch(
          value: d.homeNetwork,
          semanticLabel: 'Heimnetz-Ziel',
          onChanged: (on) => _edit(() => d.homeNetwork = on),
        ),
      ),
      SettingsRow(
        title: 'Aktiv',
        trailing: WSwitch(
          value: d.enabled,
          semanticLabel: 'Aktiv',
          onChanged: (on) => _edit(() => d.enabled = on),
        ),
      ),
      _Field(
        child: TextFormField(
          key: const ValueKey('timeout'),
          initialValue: d.timeoutSeconds,
          style: WText.body,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Zeitlimit in Sekunden',
            helperText: '1–${httpToolMaxTimeout.inSeconds}',
          ),
          onChanged: (v) => _edit(() => d.timeoutSeconds = v),
        ),
      ),
    ],
  );

  Widget _testSection(HttpToolDraft d, String? problem) {
    final types = d.argTypes();
    for (final name in types.keys) {
      _testArgs.putIfAbsent(name, TextEditingController.new);
    }
    final result = _result;
    return SettingsSection(
      title: 'Testen',
      children: [
        for (final MapEntry(key: name, value: type) in types.entries)
          _Field(
            key: ValueKey('testArg-$name'),
            child: TextField(
              key: ValueKey('testArg$name'),
              controller: _testArgs[name],
              style: WText.mono,
              decoration: InputDecoration(labelText: '$name ($type)'),
            ),
          ),
        _Field(
          child: WideButton(
            _testing ? 'Läuft …' : 'Testen',
            onPressed: problem == null && !_testing
                ? () => unawaited(_test())
                : null,
          ),
        ),
        if (_testError != null)
          _Field(
            child: Text(
              _testError!,
              style: WText.caption.copyWith(color: WColors.error),
            ),
          ),
        if (result != null) HttpTestResultView(result),
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

String _pretty(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);

/// Padding of a form field inside a [SectionCard].
class _Field extends StatelessWidget {
  const _Field({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WSpace.l,
      vertical: WSpace.s,
    ),
    child: child,
  );
}

/// Result of a test run: status, duration, the request as sent (secrets
/// as `••••••`) and the shortened answer.
class HttpTestResultView extends StatelessWidget {
  /// Creates the view.
  const HttpTestResultView(this.result, {super.key});

  /// The result.
  final HttpToolTestResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final ms = r.duration.inMilliseconds;
    final status = [
      if (r.status != null) 'HTTP ${r.status}' else 'Keine Antwort',
      '$ms ms',
      if (r.truncated) 'gekürzt',
    ].join(' · ');
    final request = r.request;
    return Padding(
      padding: const EdgeInsets.all(WSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WSpace.s,
        children: [
          Row(
            spacing: WSpace.s,
            children: [
              CheckStatusIcon(
                r.ok ? CheckStatus.ok : CheckStatus.failed,
                size: WSize.statusIconSmall,
                semanticLabel: r.ok ? 'erfolgreich' : 'fehlgeschlagen',
              ),
              Expanded(child: Text(status, style: WText.label)),
            ],
          ),
          if (r.error != null)
            Text(r.error!, style: WText.caption.copyWith(color: WColors.error)),
          if (request != null) ...[
            Text('Gesendet', style: WText.sectionLabel),
            SelectableText(
              [
                '${request.method} ${request.url}',
                for (final e in request.headers.entries) '${e.key}: ${e.value}',
                if (request.body != null) ...['', request.body!],
              ].join('\n'),
              style: WText.mono,
            ),
          ],
          if (r.preview.isNotEmpty) ...[
            Text('Antwort', style: WText.sectionLabel),
            SelectableText(r.preview, style: WText.mono),
          ],
        ],
      ),
    );
  }
}

/// Text field that highlights `{placeholder}`s: known arguments in the
/// accent colour, unknown ones in the error colour.
class PlaceholderTextController extends TextEditingController {
  /// Creates the controller; [known] gives the argument names.
  PlaceholderTextController({super.text, required this.known});

  /// Names of the arguments.
  final Set<String> Function() known;

  static final _placeholder = RegExp(r'\{([^{}]*)\}');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final names = known();
    final children = <TextSpan>[];
    var last = 0;
    for (final m in _placeholder.allMatches(text)) {
      if (m.start > last) {
        children.add(TextSpan(text: text.substring(last, m.start)));
      }
      final ok = names.contains(m[1]);
      children.add(
        TextSpan(
          text: m[0],
          style: TextStyle(
            color: ok ? WColors.accentLight : WColors.error,
            fontWeight: FontWeight.w600,
          ),
          semanticsLabel: ok ? null : '${m[0]} unbekannt',
        ),
      );
      last = m.end;
    }
    if (last < text.length) children.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: children);
  }
}
