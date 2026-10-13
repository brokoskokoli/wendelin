import 'package:flutter/material.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../design/design.dart';
import '../settings_page.dart';
import 'editor_parts.dart';

/// „Testen“: one field per argument, the test button and the result.
class TestRunPanel extends StatelessWidget {
  /// Creates the panel.
  const TestRunPanel({
    super.key,
    required this.argTypes,
    required this.controllers,
    required this.canTest,
    required this.testing,
    required this.onTest,
    this.error,
    this.result,
  });

  /// Argument names with their types.
  final Map<String, String> argTypes;

  /// Controller per argument name.
  final Map<String, TextEditingController> controllers;

  /// The draft is valid and no test is running.
  final bool canTest;

  /// A test is running.
  final bool testing;

  /// Starts the test.
  final VoidCallback onTest;

  /// Why the last test could not start.
  final String? error;

  /// Result of the last test.
  final HttpToolTestResult? result;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final result = this.result;
    return SettingsSection(
      title: 'Testen',
      children: [
        for (final MapEntry(key: name, value: type) in argTypes.entries)
          EditorField(
            key: ValueKey('testArg-$name'),
            child: TextField(
              key: ValueKey('testArg$name'),
              controller: controllers[name],
              style: WText.mono,
              decoration: InputDecoration(labelText: '$name ($type)'),
            ),
          ),
        EditorField(
          child: WideButton(
            testing ? 'Läuft …' : 'Testen',
            onPressed: canTest ? onTest : null,
          ),
        ),
        if (error != null)
          EditorField(
            child: Text(
              error,
              style: WText.caption.copyWith(color: WColors.error),
            ),
          ),
        if (result != null) HttpTestResultView(result),
      ],
    );
  }
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
