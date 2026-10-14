import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/ui/attestation/attestation_texts.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/conversation_view.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'helpers.dart';

AnswerAttestation _a(
  AttestationStatus s, {
  String? reason,
  String log = 'l1',
  bool tools = false,
}) => AnswerAttestation(
  stepId: 's:1',
  status: s,
  logId: log,
  reasonCode: reason,
  toolsInvolved: tools,
);

Widget _answer(
  AnswerAttestation a, {
  ValueChanged<AnswerAttestation>? onTap,
  ValueChanged<AnswerAttestation>? onReattest,
}) => SizedBox(
  width: 350,
  child: AttestedAnswer(
    answer: const Text('Ruhig: 0,4 m Welle.'),
    attestation: a,
    onTap: onTap,
    onReattest: onReattest,
  ),
);

void main() {
  group('Schild', () {
    for (final (status, label) in [
      (AttestationStatus.green, 'geprüft'),
      (AttestationStatus.yellow, 'wird geprüft'),
      (AttestationStatus.red, 'Prüfung fehlgeschlagen'),
    ]) {
      testWidgets('${status.name}: Text, Symbol, Screenreader, Tippfläche', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        AnswerAttestation? tapped;
        await tester.pumpWidget(
          themed(Scaffold(body: _answer(_a(status), onTap: (a) => tapped = a))),
        );
        expect(
          find.descendant(
            of: find.byType(AttestationShield),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('TEE-Prüfung: $label')),
          findsOneWidget,
        );
        final box = tester.getSize(find.byType(AttestationShield));
        expect(box.height, greaterThanOrEqualTo(WSize.touchMin));
        await tester.tap(find.byType(AttestationShield));
        expect(tapped?.logId, 'l1');
        handle.dispose();
      });
    }

    testWidgets('Rot zeigt die Warnkarte mit „Neu prüfen“, Grün nicht', (
      tester,
    ) async {
      var rechecks = 0;
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: _answer(
              _a(AttestationStatus.red),
              onReattest: (_) => rechecks++,
            ),
          ),
        ),
      );
      expect(find.text('Prüfung fehlgeschlagen'), findsNWidgets(2));
      await tester.tap(find.text('Neu prüfen'));
      expect(rechecks, 1);
      await tester.pumpWidget(
        themed(Scaffold(body: _answer(_a(AttestationStatus.green)))),
      );
      expect(find.byType(StatusCard), findsNothing);
    });

    testWidgets('Sonderfälle haben eigene Texte', (tester) async {
      Future<void> show(String? reason) => tester.pumpWidget(
        themed(
          Scaffold(
            body: SingleChildScrollView(
              child: _answer(
                _a(AttestationStatus.red, reason: reason),
                onReattest: (_) {},
              ),
            ),
          ),
        ),
      );
      await show(AttestationReason.tcbOutOfDate);
      expect(
        find.text('Sicherheits-Update beim Betreiber ausstehend'),
        findsOneWidget,
      );
      expect(
        find.textContaining('kein Hinweis auf eine Manipulation'),
        findsOneWidget,
      );
      await show(AttestationReason.relaunchAdvised);
      expect(
        find.text('Neustart der TEE beim Betreiber empfohlen'),
        findsOneWidget,
      );
      await show(AttestationReason.sessionMismatch);
      expect(find.text('Möglicher Manipulationsversuch'), findsOneWidget);
      await show(null);
      expect(find.textContaining('Signaturfehlers'), findsOneWidget);
      expect(
        find.text('Sicherheits-Update beim Betreiber ausstehend'),
        findsNothing,
        reason: 'Manipulation darf nicht wie ein Update-Rückstand klingen',
      );
      await show(AttestationReason.gpuFailed);
      expect(find.text('GPU-Prüfung fehlgeschlagen'), findsNWidgets(2));
      expect(
        find.text('Neu prüfen'),
        findsNothing,
        reason: 'GPU: nur vorher fragen',
      );
    });
  });

  group('Texte', () {
    test('jeder Code hat Titel und Text, Grün und Gelb nicht', () {
      for (final code in [
        AttestationReason.tcbOutOfDate,
        AttestationReason.relaunchAdvised,
        AttestationReason.tcbRevoked,
        AttestationReason.sessionMismatch,
        AttestationReason.gpuFailed,
        AttestationReason.gpuUnavailable,
        null,
      ]) {
        final m = attestationMessage(AttestationStatus.red, reasonCode: code);
        expect(m.status, CheckStatus.failed);
        expect(m.title, isNotEmpty);
        expect(m.text, isNotEmpty);
      }
      expect(attestationMessage(AttestationStatus.green).title, isNull);
      expect(
        attestationMessage(AttestationStatus.yellow).status,
        CheckStatus.pending,
      );
    });

    test('Stufen und Ergebnisse haben deutsche Namen', () {
      expect(stageLabel('quote'), 'TDX-Quote (DCAP)');
      expect(stageLabel('unbekannt'), 'unbekannt');
      expect(stageResultLabel('pass'), 'bestanden');
      expect(stageResultStatus('info'), isNull);
      expect(stageResultStatus('fail'), CheckStatus.failed);
    });
  });

  group('Tool-Hinweis (WP63)', () {
    testWidgets('nur an Antworten mit Tools', (tester) async {
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: Column(
              children: [
                _answer(_a(AttestationStatus.green)),
                _answer(_a(AttestationStatus.green, tools: true)),
              ],
            ),
          ),
        ),
      );
      expect(find.text(ToolTlsHint.text), findsOneWidget);
      expect(
        find.text('Tool-Argumente nur über gepinntes TLS geschützt'),
        findsOneWidget,
      );
    });

    testWidgets('Golden Schild mit und ohne Tool-Hinweis', tags: ['golden'], (
      tester,
    ) async {
      await pumpComponent(tester, [
        _answer(_a(AttestationStatus.green)),
        _answer(_a(AttestationStatus.green, tools: true)),
      ]);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/components/tool_tls_hint.png'),
      );
    });
  });

  test('Stufentexte: E2EE und TLS', () {
    expect(stageLabel('e2ee.key'), 'E2EE-Schlüssel geprüft');
    expect(stageLabel('tls.spki'), 'TLS-Verbindung geprüft');
    expect(stageExplanation('e2ee.key'), contains('nicht im Modell selbst'));
    expect(stageExplanation('quote'), isNull);
  });

  testWidgets(
    'Golden Schild in drei Zuständen und Warnkarten',
    tags: ['golden'],
    (tester) async {
      await pumpComponent(tester, [
        _answer(_a(AttestationStatus.green)),
        _answer(_a(AttestationStatus.yellow, log: '')),
        _answer(_a(AttestationStatus.red), onReattest: (_) {}),
        _answer(
          _a(AttestationStatus.red, reason: AttestationReason.tcbOutOfDate),
          onReattest: (_) {},
        ),
        _answer(
          _a(AttestationStatus.red, reason: AttestationReason.relaunchAdvised),
          onReattest: (_) {},
        ),
      ]);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/components/attestation_shield.png'),
      );
    },
  );

  testWidgets(
    'Gespräch: Schild unter der Antwort, Tippen reicht den Status weiter',
    (tester) async {
      AnswerAttestation? tapped;
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: ConversationView(
              entries: [
                const UserEntry('u', 'Frage'),
                AssistantTextEntry(
                  'a',
                  'Antwort',
                  attestation: _a(AttestationStatus.green),
                ),
                const AssistantTextEntry('b', 'Lokale Antwort'),
              ],
              now: DateTime(2026, 10, 13, 8, 12),
              onUndo: (_) {},
              onAttestationTap: (a) => tapped = a,
            ),
          ),
        ),
      );
      expect(find.byType(AttestationShield), findsOneWidget);
      await tester.tap(find.text('geprüft'));
      expect(tapped?.stepId, 's:1');
    },
  );
}
