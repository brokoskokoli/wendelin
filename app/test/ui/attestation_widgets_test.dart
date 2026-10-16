import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/tee_restrictions.dart';
import 'package:wendelin/ui/attestation/attestation_texts.dart';
import 'package:wendelin/ui/attestation/stage_line.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/conversation_view.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'helpers.dart';

/// [themed] with the open (not accepted) restrictions of every log entry.
Widget scoped(Widget child, {Set<String> open = const {}}) => ProviderScope(
  overrides: [openRestrictionsProvider.overrideWith((ref, id) async => open)],
  child: themed(child),
);

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
  Set<String> open = const {},
}) => ProviderScope(
  overrides: [openRestrictionsProvider.overrideWith((ref, id) async => open)],
  child: SizedBox(
    width: 350,
    child: AttestedAnswer(
      answer: const Text('Ruhig: 0,4 m Welle.'),
      attestation: a,
      onTap: onTap,
      onReattest: onReattest,
    ),
  ),
);

CheckStatus _shieldStatus(WidgetTester tester) => tester
    .widget<AttestationShield>(find.byKey(const ValueKey('answerShield')))
    .status;

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
          scoped(Scaffold(body: _answer(_a(status), onTap: (a) => tapped = a))),
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
        scoped(
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
        scoped(Scaffold(body: _answer(_a(AttestationStatus.green)))),
      );
      expect(find.byType(StatusCard), findsNothing);
    });

    testWidgets('Nicht bestätigt: graues Schild und neutrale Karte', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        scoped(
          Scaffold(
            body: SingleChildScrollView(
              child: _answer(
                _a(
                  AttestationStatus.unconfirmed,
                  reason: AttestationReason.receiptNotFound,
                ),
                onReattest: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp('TEE-Prüfung: nicht bestätigt')),
        findsOneWidget,
      );
      expect(find.text('Quittung nicht gefunden'), findsOneWidget);
      expect(find.textContaining('Signaturfehler'), findsNothing);
      handle.dispose();
    });

    testWidgets('Sonderfälle haben eigene Texte', (tester) async {
      Future<void> show(String? reason) => tester.pumpWidget(
        scoped(
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
    test('Quittungsgründe: Grund genannt, neutral, keine Manipulation, '
        'nichts verharmlost', () {
      final texts = {
        for (final code in [
          AttestationReason.receiptNotFound,
          AttestationReason.receiptUnreachable,
          AttestationReason.receiptMissing,
        ])
          code: attestationMessage(
            AttestationStatus.unconfirmed,
            reasonCode: code,
          ),
      };
      expect(texts.values.map((m) => m.title).toSet(), hasLength(3));
      for (final m in texts.values) {
        expect(m.status, CheckStatus.neutral);
        expect(m.label, 'nicht bestätigt');
        expect(m.text, isNot(contains('Signaturfehlers')));
        expect(m.text, isNot(contains('Das kann auf eine Manipulation')));
        expect(m.text, isNot(contains('Schlüssel')));
        expect(
          m.text,
          contains(
            'Ob die Antwort aus der geprüften Umgebung stammt, ist '
            'unbestätigt.',
          ),
        );
        expect(m.text, contains('Aktionen'));
      }
      expect(
        texts[AttestationReason.receiptNotFound]!.text,
        contains('kennt die Quittung'),
      );
      expect(
        texts[AttestationReason.receiptUnreachable]!.text,
        contains('Netz- oder Serverfehler'),
      );
      final rejected = attestationMessage(
        AttestationStatus.red,
        reasonCode: AttestationReason.receiptRejected,
      );
      expect(rejected.status, CheckStatus.failed);
      expect(rejected.text, isNot(contains('Schlüssel')));
    });

    test('jeder Code hat Titel und Text, Grün und Gelb nicht', () {
      for (final code in [
        AttestationReason.tcbOutOfDate,
        AttestationReason.relaunchAdvised,
        AttestationReason.tcbRevoked,
        AttestationReason.sessionMismatch,
        AttestationReason.gpuFailed,
        AttestationReason.gpuUnavailable,
        AttestationReason.receiptRejected,
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

    test('GPU-Fehler nennt den Grund (WP77)', () {
      final m = attestationMessage(
        AttestationStatus.red,
        reasonCode: AttestationReason.gpuFailed,
        detail: 'GPU-Prüfung: NRAS lehnt die Evidenz ab (HTTP 400, INVALID_EVIDENCE)',
      );
      expect(m.text, contains('Grund: NRAS lehnt die Evidenz ab'));
      expect(m.text, contains('INVALID_EVIDENCE'));
      final none = attestationMessage(
        AttestationStatus.red,
        reasonCode: AttestationReason.gpuUnavailable,
      );
      expect(none.text, isNot(contains('Grund')));
      expect(
        gpuBlockReason(
          'GPU-Prüfung nicht bestanden (Zeitüberschreitung [timeout]); '
          'Anfrage nicht gesendet',
        ),
        ' Grund: Zeitüberschreitung.',
      );
      expect(gpuBlockReason('anderer Text'), isEmpty);
    });

    test('Stufen und Ergebnisse haben deutsche Namen', () {
      expect(stageLabel('quote'), 'TDX-Quote (DCAP)');
      expect(stageLabel('unbekannt'), 'unbekannt');
      expect(stageResultLabel('pass'), 'bestanden');
      expect(stageResultStatus('info'), CheckStatus.info);
      expect(stageResultStatus('fail'), CheckStatus.failed);
    });
  });

  group('Chat nur mit Haken (WP78)', () {
    testWidgets('kein Tool-Hinweis mehr im Chat, auch mit Tools', (
      tester,
    ) async {
      await tester.pumpWidget(
        scoped(
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
      await tester.pump();
      expect(find.text(ToolTlsHint.text), findsNothing);
      expect(find.text('geprüft'), findsNWidgets(2));
    });

    testWidgets('akzeptierte Einschränkung: schlichtes grünes Schild', (
      tester,
    ) async {
      await tester.pumpWidget(
        scoped(Scaffold(body: _answer(_a(AttestationStatus.green)))),
      );
      await tester.pump();
      expect(find.text('geprüft'), findsOneWidget);
      expect(find.text(restrictionOpenLabel), findsNothing);
      expect(_shieldStatus(tester), CheckStatus.ok);
    });

    testWidgets('neue Einschränkung: graues Schild mit Hinweis', (
      tester,
    ) async {
      await tester.pumpWidget(
        scoped(
          Scaffold(
            body: _answer(_a(AttestationStatus.green), open: {'provenance'}),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(restrictionOpenLabel), findsOneWidget);
      expect(find.text('geprüft'), findsNothing);
      // Grey info symbol, not the green check.
      expect(_shieldStatus(tester), CheckStatus.info);
    });

    testWidgets('Rot und Grau bleiben von Einschränkungen unberührt', (
      tester,
    ) async {
      await tester.pumpWidget(
        scoped(
          Scaffold(
            body: Column(
              children: [
                _answer(_a(AttestationStatus.red), open: {'provenance'}),
                _answer(
                  _a(
                    AttestationStatus.unconfirmed,
                    reason: AttestationReason.receiptNotFound,
                  ),
                  open: {'provenance'},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Prüfung fehlgeschlagen'), findsWidgets);
      expect(find.text('nicht bestätigt'), findsOneWidget);
      expect(find.text(restrictionOpenLabel), findsNothing);
    });

    testWidgets('Golden Schild, Tools ohne Hinweis', tags: ['golden'], (
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
        scoped(
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

  testWidgets('jede Stufe hat ein Symbol, auch „nur protokolliert“', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    expect(stageResultStatus('pass'), CheckStatus.ok);
    expect(stageResultStatus('fail'), CheckStatus.failed);
    expect(stageResultStatus('warn'), CheckStatus.pending);
    expect(stageResultStatus('info'), CheckStatus.info);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StageLine(
            label: 'Frische',
            result: stageResultLabel('info'),
            status: stageResultStatus('info'),
          ),
        ),
      ),
    );
    expect(find.byType(CheckStatusIcon), findsOneWidget);
    expect(find.bySemanticsLabel('nur protokolliert'), findsOneWidget);
    handle.dispose();
  });
}
