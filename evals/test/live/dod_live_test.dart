@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

// Live-Durchlauf M1 (WP11): der DoD-Satz „Trag mir morgen um 10 Tauchen
// ein“ durch die echte Agent-Schleife (AgentRunner, ToolRegistry,
// ToolExecutor, Kalender-Integration) mit Fake-Kalenderport, je Profil aus
// `profiles/`. Dazu Proben zu WP14: Anthropic (und OpenAI) mit
// ausgeblendeten tool_use-Blöcken und aufeinanderfolgenden
// Nutzernachrichten, wie sie `AgentRunner._messagesFor` erzeugt.
//
// Keys nur aus der Umgebung, nie ausgeben. Start (im Verzeichnis evals/):
//   set -a; . ~/.wendelin-live.env; set +a
//   dart test test/live -t live --run-skipped

final _env = Platform.environment;

EvalProfile _profile(String name) =>
    EvalProfile.parse(File('profiles/$name.json').readAsStringSync());

String? _key(EvalProfile p) {
  final v = p.apiKeyVariable;
  final key = v == null ? null : _env[v];
  return key == null || key.trim().isEmpty ? null : key;
}

LlmProvider _adapter(EvalProfile p) =>
    ProviderFactory.create(p.profile, (_) async => _key(p), catalog: p.catalog);

// ignore: avoid_print
void _log(String line) => print(line);

void _dodSuite(String profileName) {
  final profile = _profile(profileName);
  final p = profile.profile;
  group('DoD ${p.id} (${p.defaultModel})', () {
    test('„Trag mir morgen um 10 Tauchen ein“ legt den Termin an', () async {
      final tauchen = loadCases(Directory('cases'))
          .singleWhere((c) => c.id == 'de-cal-tauchen');
      final adapter = _adapter(profile);
      final runner = EvalRunner(
        target: EvalTarget(
          profileId: p.id,
          modelId: p.defaultModel,
          privacy: p.privacy,
          provider: (_) => adapter,
          costEstimator: profile.costEstimator,
        ),
        time: EvalTime.parse(defaultNow, defaultTimeZone),
      );
      final r = await runner.runCase(tauchen);
      final o = r.observation;
      _log(
        'DoD ${p.id}/${p.defaultModel}: ${r.status.name}, '
        '${o.latency.inMilliseconds} ms, ${o.modelCalls} Modellaufrufe, '
        '${o.usage}, Kosten ${o.costMicros ?? '?'} µUSD, '
        'Calls: ${o.calls.map((c) => '${c.name} ${c.rawArguments}').join('; ')}'
        ', Antwort: ${o.finalText}',
      );
      expect(r.status, CaseStatus.passed, reason: r.reasons.join('; '));
    });
  }, skip: _key(profile) == null ? '${profile.apiKeyVariable} fehlt' : false);
}

const _otherTool = ToolSpec(
  name: 'clipboard__read',
  description: 'Liest die Zwischenablage.',
  inputSchema: {'type': 'object', 'properties': <String, Object?>{}},
);

const _placeholder = '[Inhalt aus geschützter Quelle ausgeblendet]';
const _redacted = '[Tool-Ergebnis aus geschützter Quelle ausgeblendet]';

Future<void> _expectAccepted(
  LlmProvider adapter,
  String model,
  List<Message> messages, {
  List<ToolSpec> tools = const [],
  required String label,
}) async {
  final events = await adapter
      .chat(
        ChatRequest(
          systemPrompt: 'Antworte knapp auf Deutsch.',
          messages: messages,
          tools: tools,
          model: model,
          maxTokens: 400,
        ),
      )
      .toList();
  final usage = events.whereType<UsageEvent>().fold(
    Usage.zero,
    (s, e) => s + e.usage,
  );
  final cost = CostCalculator(ModelCatalog.builtIn()).costMicros(model, usage);
  final error = events.whereType<ErrorEvent>().firstOrNull;
  _log(
    '$label ($model): ${error ?? events.last}, $usage, '
    'Kosten ${cost ?? '?'} µUSD',
  );
  expect(error, isNull, reason: '$label: API hat abgelehnt');
  expect(events.last, isA<Done>());
}

void _historySuite(String profileName) {
  final profile = _profile(profileName);
  final model = profile.profile.defaultModel;
  group('WP14-Verlauf ${profile.profile.id}', () {
    test('ausgeblendeter Tool-Aufruf (Tool nicht in der Liste, Args {})', () {
      // Sicht eines Ziels ohne Kalender-Tools auf einen früheren Lauf mit
      // Kalender (AgentRunner._messagesFor mit hasTools = true).
      return _expectAccepted(
        _adapter(profile),
        model,
        [
          Message.user('Was steht morgen an?'),
          Message(Role.assistant, [
            const ToolCallBlock(
              id: 'toolu_hidden_1',
              name: 'calendar__list_events',
              argumentsJson: '{}',
            ),
          ]),
          Message(Role.tool, [
            ToolResultBlock(
              callId: 'toolu_hidden_1',
              content: [const TextBlock(_redacted)],
            ),
          ]),
          Message(Role.assistant, [const TextBlock(_placeholder)]),
          Message.user('Danke. Antworte nur mit „ok“.'),
        ],
        tools: const [_otherTool],
        label: 'ausgeblendeter tool_use',
      );
    });

    test(
      'ohne Tools: Aufrufe als Text, aufeinanderfolgende Nutzernachrichten',
      () {
        // hasTools = false: Tool-Aufruf und -Ergebnis werden Text, die
        // Tool-Nachricht wird zur Nutzernachricht – direkt vor der nächsten
        // Nutzernachricht.
        return _expectAccepted(_adapter(profile), model, [
          Message.user('Was steht morgen an?'),
          Message(Role.assistant, [
            const TextBlock('[Tool-Aufruf: calendar__list_events]'),
          ]),
          Message(Role.user, [const TextBlock('[Tool-Ergebnis: $_redacted]')]),
          Message.user('Danke. Antworte nur mit „ok“.'),
        ], label: 'aufeinanderfolgende Nutzernachrichten');
      },
    );
  }, skip: _key(profile) == null ? '${profile.apiKeyVariable} fehlt' : false);
}

void main() {
  _dodSuite('claude-haiku');
  _dodSuite('openai-mini');
  _dodSuite('phala-tee-small');
  _historySuite('claude-haiku');
  _historySuite('openai-mini');
}
