import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
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

  Future<CaseResult> run(String id, {bool fastPath = false}) {
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
      fastPath: fastPath,
    ).runCase(c);
  }

  /// id → (model calls, tool calls, errors among them). VORHER (Stand vor
  /// WP135 A–C): licht-aus 1/1/0, lampe-an 3/3/1, rollo-runter 2/1/0,
  /// rollo-rauf 2/1/0, rollo-50 2/1/1. NACHHER (A–C): überall 1/1/0; die
  /// Rollo-Fälle gehen ohne Rückfrage über ha__call_secure nur im Skript, das
  /// weiter dieses Werkzeug wählt. Das Skript ist fest (kein echtes Modell)
  /// und nennt das Gerät schon beim ersten Aufruf, wie es mit Geräteliste im
  /// Prompt wäre; echte Läufe schwanken mehr.
  const expected = <String, (int, int, int)>{
    'de-ha-licht-aus': (1, 1, 0),
    'de-ha-lampe-an': (1, 1, 0),
    'de-ha-rollo-runter': (1, 1, 0),
    'de-ha-rollo-rauf': (1, 1, 0),
    'de-ha-rollo-50': (1, 1, 0),
    'de-ha-kaffee-an': (1, 1, 0),
    // WP150: „100“ als String führt nicht mehr zu einem Fehlaufruf.
    'de-ha-annas-licht-an': (1, 1, 0),
    'de-ha-annas-licht-aus': (1, 1, 0),
    'de-ha-annas-licht-100': (1, 1, 0),
    // Ein nacktes „Licht an“ ist mehrdeutig: das Modell antwortet.
    'de-ha-licht-nackt': (1, 0, 0),
  };

  /// Mit Schnellweg (D): einfache Befehle ohne Modellaufruf, nur der Werkzeug-
  /// aufruf bleibt. „Lampe Wohnzimmer an“ trifft über das Typwort das Licht.
  const withFastPath = <String, (int, int, int)>{
    'de-ha-licht-aus': (0, 1, 0),
    'de-ha-lampe-an': (0, 1, 0),
    'de-ha-rollo-runter': (0, 1, 0),
    'de-ha-rollo-rauf': (0, 1, 0),
    'de-ha-rollo-50': (0, 1, 0),
    'de-ha-kaffee-an': (0, 1, 0),
    'de-ha-annas-licht-an': (0, 1, 0),
    'de-ha-annas-licht-aus': (0, 1, 0),
    'de-ha-licht-nackt': (1, 0, 0),
  };

  for (final id in expected.keys) {
    test(id, () async {
      final r = await run(id);
      final o = r.observation;
      stdout.writeln(
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

  for (final id in withFastPath.keys) {
    test('$id (Schnellweg)', () async {
      final o = (await run(id, fastPath: true)).observation;
      stdout.writeln(
        'MESSUNG schnellweg $id modell=${o.modelCalls} '
        'tools=${o.calls.length} text="${o.finalText}"',
      );
      expect((
        o.modelCalls,
        o.calls.length,
        o.calls.where((x) => x.isError).length,
      ), withFastPath[id]);
    });
  }
}
