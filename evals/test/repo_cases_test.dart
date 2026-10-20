import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

/// Checks the shipped case files: counts per language, required case kinds
/// and that every expected tool exists (except pending ones).
void main() {
  final cases = loadCases(Directory('cases'));
  final active = cases.where((c) => !c.pending).toList();

  test('150 aktive Fälle: de 70, en 40, fr 40', () {
    int count(String l) => active.where((c) => c.language == l).length;
    expect(active, hasLength(150));
    expect((count('de'), count('en'), count('fr')), (70, 40, 40));
  });

  test('Fälle je Integration und Sprache (eigene Dateien, WP112)', () {
    // Datei -> (de, en, fr)
    const perFile = {
      'calendar.yaml': (6, 3, 3),
      'tasks.yaml': (5, 3, 3),
      'bring.yaml': (5, 3, 3),
      'spotify.yaml': (5, 3, 3),
      'weather.yaml': (5, 3, 3),
      'web.yaml': (2, 2, 2),
      'alarm.yaml': (5, 3, 3),
      'notes.yaml': (4, 3, 3),
      'memory.yaml': (2, 0, 0),
      'station.yaml': (2, 1, 1),
      'multistep.yaml': (3, 2, 2),
      'clarify.yaml': (3, 2, 2),
      'refuse.yaml': (3, 2, 2),
    };
    for (final MapEntry(key: file, value: want) in perFile.entries) {
      final cs = parseCaseFile(File('cases/$file').readAsStringSync());
      int n(String l) => cs.where((c) => c.language == l).length;
      expect((n('de'), n('en'), n('fr')), want, reason: file);
      expect(cs.every((c) => !c.pending), isTrue, reason: file);
    }
    // Jede neue M5-Integration hat Fälle mit ihrem Fake-Backend.
    for (final b in [
      'bring',
      'gtasks',
      'spotify',
      'weather',
      'station',
      'notes',
    ]) {
      expect(
        active.where((c) => c.setup.backends.contains(b)).length,
        greaterThanOrEqualTo(4),
        reason: b,
      );
    }
  });

  test(
    'Rückfragen ohne Tool, Ablehnungen mit forbid, Mehrschritt mit 2 Aufrufen',
    () {
      final clarify = active.where((c) => c.category == 'clarify').toList();
      expect(clarify.length, 7);
      for (final c in clarify) {
        expect(c.expect.noTools, isTrue, reason: c.id);
        expect(c.expect.text, isNotNull, reason: c.id);
      }
      final refuse = active.where((c) => c.category == 'refuse').toList();
      expect(refuse.length, 7);
      for (final c in refuse) {
        expect(c.expect.forbid, isNotEmpty, reason: c.id);
      }
      final multi = active.where((c) => c.category == 'multistep').toList();
      expect(multi.length, 7);
      for (final c in multi) {
        expect(c.expect.calls.length, greaterThanOrEqualTo(2), reason: c.id);
      }
      // station__start bleibt ohne Sprachbefehl zum Beenden.
      expect(
        active.any((c) => c.id == 'de-station-beenden' && c.expect.noTools),
        isTrue,
      );
    },
  );

  test('alle Fälle laufen grün gegen das volle Fake-Skript', () async {
    final out = StringBuffer();
    final code = await runCli(
      ['-p', 'profiles/fake-full.json'],
      env: const {},
      out: out,
      err: out,
    );
    expect(code, 0, reason: '$out');
    expect(out.toString(), matches(r'gesamt\s+150/150'));
    expect(out.toString(), matches(r'de\s+70/70'));
    expect(out.toString(), matches(r'en\s+40/40'));
    expect(out.toString(), matches(r'fr\s+40/40'));
  });

  test('das volle Fake-Skript deckt genau die aktiven Fälle ab', () {
    final script = FakeScript.parse(
      File('fake/full_script.yaml').readAsStringSync(),
    );
    expect(script.caseIds.toSet(), active.map((c) => c.id).toSet());
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
      // Je Backend-Menge einmal durchlaufen lassen, damit die Registry
      // gebaut wird; die Tool-Namen kommen aus den echten Integrationen.
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
      final known = <String, Set<String>>{};
      for (final c in active) {
        final key = ([...c.setup.backends]..sort()).join(',');
        if (known.containsKey(key)) continue;
        provider.toolNames.clear();
        await runner.runCase(c);
        known[key] = {...provider.toolNames};
      }
      expect(known[''], contains('calendar__create_event'));
      for (final c in active) {
        final names = known[([...c.setup.backends]..sort()).join(',')]!;
        for (final name in [
          ...c.expect.calls.expand((e) => e.toolNames),
          ...c.expect.forbid,
        ]) {
          expect(names, contains(name), reason: '${c.id}: $name');
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
