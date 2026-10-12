import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

/// Checks the shipped case files: counts per language, required case kinds
/// and that every expected tool exists (except pending ones).
void main() {
  final cases = loadCases(Directory('cases'));
  final active = cases.where((c) => !c.pending).toList();

  test('40 aktive Fälle: de 20, fr 10, en 10', () {
    int count(String l) => active.where((c) => c.language == l).length;
    expect(active, hasLength(40));
    expect((count('de'), count('fr'), count('en')), (20, 10, 10));
  });

  test(
    'enthält den Tauchen-Fall, No-Tool-Fälle und external-Löschen je Sprache',
    () {
      expect(
        active.any((c) => c.prompt == 'Trag mir morgen um 10 Tauchen ein'),
        isTrue,
      );
      expect(
        active
            .where((c) => c.category == 'smalltalk' && c.expect.noTools)
            .length,
        greaterThanOrEqualTo(3),
      );
      expect(
        active.where((c) => c.category == 'text' && c.expect.noTools),
        isNotEmpty,
      );
      for (final l in ['de', 'fr', 'en']) {
        expect(
          active.any(
            (c) =>
                c.language == l &&
                c.expect.confirmed == true &&
                c.expect.calls.any(
                  (e) => e.toolNames.contains('calendar__delete_event'),
                ),
          ),
          isTrue,
          reason: l,
        );
      }
      for (final category in [
        'calendar',
        'alarms',
        'memory',
        'clipboard',
        'web',
      ]) {
        expect(
          active.where((c) => c.category == category),
          isNotEmpty,
          reason: category,
        );
      }
    },
  );

  test(
    'keine Werte aus den Beispielen der Tool-Beschreibungen (Review #2)',
    () {
      // „morgen“ darf nicht das Beispieldatum 2026-10-15 sein.
      final time = EvalTime.parse(defaultNow, defaultTimeZone);
      expect(time.resolve('+1d').toIso(), '2026-11-19');
      final text = [
        for (final f in Directory('cases').listSync().whereType<File>())
          f.readAsStringSync(),
      ].join('\n');
      for (final example in [
        RegExp(r'duration_seconds: (600|90)\b'),
        RegExp(r'clock: "(06:45|07:30)"'),
        RegExp(r'days: \[1, 2, 3, 4, 5\]'),
      ]) {
        expect(example.hasMatch(text), isFalse, reason: example.pattern);
      }
    },
  );

  test('zwei Listen-Fälle (K6) sind pending', () {
    final pending = cases.where((c) => c.pending).toList();
    expect(pending.map((c) => c.id), ['de-lists-add', 'de-lists-get']);
    final tools = pending
        .expand((c) => c.expect.calls)
        .expand((e) => e.toolNames);
    expect(tools, containsAll(['lists__add_items', 'lists__get_items']));
  });

  test(
    'alle erwarteten Tools existieren und Zeitangaben sind gültig',
    () async {
      // Einmal durchlaufen lassen, damit die Registry gebaut wird; die
      // Tool-Namen kommen aus den echten Integrationen.
      final provider = FakeLlmProviderForNames();
      final runner = EvalRunner(
        target: EvalTarget(
          profileId: 'p',
          modelId: 'm',
          privacy: PrivacyLevel.standard,
          provider: (_) => provider,
        ),
        time: EvalTime.parse(defaultNow, defaultTimeZone),
      );
      await runner.runCase(active.first);
      final known = provider.toolNames;
      expect(known, contains('calendar__create_event'));
      for (final c in active) {
        for (final name in [
          ...c.expect.calls.expand((e) => e.toolNames),
          ...c.expect.forbid,
        ]) {
          expect(known, contains(name), reason: '${c.id}: $name');
        }
        final time = EvalTime.parse(defaultNow, defaultTimeZone);
        for (final e in c.setup.events) {
          expect(() => time.resolve(e.start), returnsNormally, reason: c.id);
        }
      }
    },
  );
}

/// Records the tool names offered to the model.
final class FakeLlmProviderForNames implements LlmProvider {
  final Set<String> toolNames = {};

  @override
  ProviderCapabilities get caps =>
      const ProviderCapabilities(tools: true, vision: false, streaming: true);

  @override
  ProviderType get type => ProviderType.fake;

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    toolNames.addAll(req.tools.map((t) => t.name));
    yield const TextDelta('ok');
    yield const Done(StopReason.endTurn);
  }

  @override
  Future<List<ModelInfo>> listModels() async => const [];

  @override
  Future<HealthCheck> test() => throw UnimplementedError();
}
