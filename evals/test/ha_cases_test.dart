import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

/// Smart-home cases (WP135): how many model and tool calls typical short
/// commands need, through the production path (registry, executor, context
/// builder with the device list, fixed confirmations) with fake Home
/// Assistant and a scripted model that works like a model without a device
/// list (`fake/ha_script.yaml`). The counts measure the app side: the script
/// decides what the model asks for, so the real model's own behavior is not
/// part of this number.
void main() {
  final time = EvalTime.parse('2026-10-14T09:00', defaultTimeZone);
  final cases = loadCases(Directory('cases-ha'));
  final script = FakeScript.parse(
    File('fake/ha_script.yaml').readAsStringSync(),
  );

  Future<CaseResult> run(String id) {
    final c = cases.singleWhere((c) => c.id == id);
    return EvalRunner(
      target: EvalTarget(
        profileId: 'fake',
        modelId: 'm',
        privacy: PrivacyLevel.local,
        provider: (c) => script.providerFor(c, time),
        costEstimator: const FlatCostEstimator(),
      ),
      time: time,
    ).runCase(c);
  }

  /// id → (model calls, tool calls, errors among them). VORHER (Stand vor
  /// WP135 A–C); nach den Änderungen siehe unten.
  const expected = <String, (int, int, int)>{
    'de-ha-licht-aus': (1, 1, 0),
    'de-ha-lampe-an': (3, 3, 1),
    'de-ha-rollo-runter': (2, 1, 0),
    'de-ha-rollo-rauf': (2, 1, 0),
    'de-ha-rollo-50': (2, 1, 1),
  };

  for (final id in expected.keys) {
    test(id, () async {
      final r = await run(id);
      final o = r.observation;
      // ignore: avoid_print
      print(
        'MESSUNG $id modell=${o.modelCalls} tools=${o.calls.length} '
        'fehler=${o.calls.where((x) => x.isError).length} '
        'text="${o.finalText}"',
      );
      expect((
        o.modelCalls,
        o.calls.length,
        o.calls.where((x) => x.isError).length,
      ), expected[id]);
    });
  }
}
