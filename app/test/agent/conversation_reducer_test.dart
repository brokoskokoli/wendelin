import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_reducer.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

const reducer = ConversationReducer(nameOf: _name);

String _name(String id) => switch (id) {
  'sonnet' => 'Claude Sonnet',
  'phala' => 'Phala · GLM klein',
  _ => id,
};

final _call = ToolCallBlock(
  id: 'c1',
  name: 'calendar__create_event',
  argumentsJson: '{"title":"Tauchen"}',
);

ConversationState _apply(List<AgentEvent> events, [ConversationState? s]) =>
    events.fold(
      s ?? reducer.userMessage(ConversationState.empty, 'Hallo'),
      reducer.apply,
    );

List<String> _texts(ConversationState s) => [
  for (final e in s.entries.whereType<AssistantTextEntry>()) e.text,
];

ToolEntry _tool(ConversationState s) => s.entries.whereType<ToolEntry>().single;

void main() {
  group('userMessage', () {
    test('legt Nutzer-Eintrag an, läuft, merkt sich die Anfrage', () {
      final s = reducer.userMessage(ConversationState.empty, 'Hallo');
      expect(s.entries.single, isA<UserEntry>());
      expect((s.entries.single as UserEntry).text, 'Hallo');
      expect(s.running, isTrue);
      expect(s.lastRequest, 'Hallo');
    });

    test('neue Sitzung bekommt eine Zeitmarke davor', () {
      final at = DateTime(2026, 10, 13, 8, 12);
      final s = reducer.userMessage(
        ConversationState.empty,
        'Hallo',
        sessionStart: at,
      );
      expect(s.entries.first, isA<SessionStartEntry>());
      expect((s.entries.first as SessionStartEntry).at, at);
      expect(s.entries.map((e) => e.id).toSet(), hasLength(2));
    });
  });

  test('Routed setzt den aktiven Provider, sonst nichts', () {
    final s = _apply([
      const Routed(profileId: 'phala', modelId: 'glm', reason: 'Standard'),
    ]);
    expect(s.activeProfileId, 'phala');
    expect(s.entries, hasLength(1));
  });

  test('AgentTextDelta hängt an denselben Eintrag an', () {
    final s = _apply([
      const AgentTextDelta('Ruhig: '),
      const AgentTextDelta('0,4 m Welle'),
    ]);
    expect(_texts(s), ['Ruhig: 0,4 m Welle']);
  });

  test('Tool-Events trennen die Textabschnitte', () {
    final s = _apply([
      const AgentTextDelta('Ich trage das ein.'),
      ToolCallStarted(_call),
      ToolCallFinished(call: _call, outcome: ToolOutcome.text('ok')),
      const AgentTextDelta('Erledigt.'),
    ]);
    expect(_texts(s), ['Ich trage das ein.', 'Erledigt.']);
  });

  test('AgentSpokenText bleibt unsichtbar (WP41)', () {
    final before = reducer.apply(
      ConversationState(),
      const AgentTextDelta('Antwort'),
    );
    final after = reducer.apply(before, const AgentSpokenText('Sprechtext'));
    expect(after, same(before));
  });

  test('Prüfurteil (WP55): Treffer unsichtbar, Ablehnung als Hinweis', () {
    final before = reducer.apply(
      ConversationState(),
      const AgentTextDelta('Antwort'),
    );
    expect(reducer.apply(before, const AgentSpokenHold()), same(before));
    expect(
      reducer.apply(
        before,
        const AgentSpokenVerdict(accepted: true, reason: 'ok'),
      ),
      same(before),
    );
    final after = reducer.apply(
      before,
      const AgentSpokenVerdict(accepted: false, reason: 'anders'),
    );
    final notice = after.entries.last as NoticeEntry;
    expect(notice.text, spokenFallbackNotice);
    expect(notice.text, isNot(contains('anders')));
  });

  group('AgentTextReset', () {
    test('verwirft nur den Text des aktuellen Modellaufrufs', () {
      final s = _apply([
        const AgentTextDelta('Ich trage das ein.'),
        ToolCallStarted(_call),
        ToolCallFinished(call: _call, outcome: ToolOutcome.text('ok')),
        const AgentTextDelta('Halb fer'),
        const AgentTextReset('Wiederholung'),
        const AgentTextDelta('Erledigt.'),
      ]);
      expect(_texts(s), ['Ich trage das ein.', 'Erledigt.']);
    });

    test('ohne gestreamten Text ändert sich nichts', () {
      final before = _apply([
        const AgentTextDelta('A'),
        ToolCallStarted(_call),
      ]);
      final after = reducer.apply(before, const AgentTextReset('x'));
      expect(_texts(after), ['A']);
      expect(after.entries, hasLength(before.entries.length));
    });

    test('verwirft auch das Thinking des Aufrufs', () {
      final s = _apply([
        const AgentThinkingDelta('Hm'),
        const AgentTextDelta('Te'),
        const AgentTextReset('x'),
      ]);
      expect(s.entries.whereType<ThinkingEntry>(), isEmpty);
      expect(_texts(s), isEmpty);
    });
  });

  test('AgentThinkingDelta landet in eigenem Eintrag, nie im Text', () {
    final s = _apply([
      const AgentThinkingDelta('Überlege '),
      const AgentThinkingDelta('kurz'),
      const AgentTextDelta('Antwort'),
    ]);
    expect(s.entries.whereType<ThinkingEntry>().single.text, 'Überlege kurz');
    expect(_texts(s), ['Antwort']);
  });

  test('BudgetWarning wird ein Warnhinweis mit Beträgen', () {
    final s = _apply([
      const BudgetWarning(
        profileId: 'sonnet',
        spentMicros: 4100000,
        budgetMicros: 5000000,
      ),
    ]);
    final n = s.entries.whereType<NoticeEntry>().single;
    expect(n.kind, NoticeKind.warning);
    expect(n.text, contains('Claude Sonnet'));
    expect(n.text, contains('4,10 \$'));
    expect(n.text, contains('5,00 \$'));
    expect(s.running, isTrue);
  });

  group('Tool-Aufrufe', () {
    test('ToolCallStarted legt laufenden Eintrag an (einmalig)', () {
      final s = _apply([ToolCallStarted(_call), ToolCallStarted(_call)]);
      expect(_tool(s).phase, ToolPhase.running);
      expect(_tool(s).toolName, 'calendar__create_event');
      expect(_tool(s).integrationId, 'calendar');
    });

    test('ToolCallFinished mit Undo: erledigt, Undo-Fenster offen', () {
      final s = _apply([
        ToolCallStarted(_call),
        ToolCallFinished(
          call: _call,
          outcome: ToolOutcome.text(
            'ok',
            summary: 'Termin angelegt: Tauchen',
            undo: UndoAction(label: 'Termin entfernen', run: () async {}),
          ),
        ),
      ]);
      final t = _tool(s);
      expect(t.phase, ToolPhase.done);
      expect(t.summary, 'Termin angelegt: Tauchen');
      expect(t.undo, UndoPhase.pending);
      expect(t.undoLabel, 'Termin entfernen');
      expect(t.undoRemaining, const Duration(seconds: 10));
    });

    test('Fehler, Ablehnung und Abbruch werden unterschieden', () {
      for (final (outcome, phase) in [
        (ToolOutcome.error('kaputt'), ToolPhase.failed),
        (ToolOutcome.declined(), ToolPhase.declined),
        (ToolOutcome.cancelled(), ToolPhase.cancelled),
        (ToolOutcome.text('ok'), ToolPhase.done),
      ]) {
        final s = _apply([
          ToolCallStarted(_call),
          ToolCallFinished(call: _call, outcome: outcome),
        ]);
        expect(_tool(s).phase, phase, reason: '$outcome');
        expect(_tool(s).undo, UndoPhase.none);
      }
    });

    test('Undo eines fehlgeschlagenen Tools wird nicht angeboten', () {
      final s = _apply([
        ToolCallStarted(_call),
        ToolCallFinished(
          call: _call,
          outcome: ToolOutcome(
            content: const [TextBlock('x')],
            isError: true,
            undo: UndoAction(label: 'x', run: () async {}),
          ),
        ),
      ]);
      expect(_tool(s).undo, UndoPhase.none);
    });
  });

  group('Bestätigungen', () {
    ConfirmationRequired confirm() => ConfirmationRequired(
      call: _call,
      description: 'Termin löschen',
      respond: (_) {},
    );

    test('ConfirmationRequired öffnet die Frage mit Anfrage-Zitat', () {
      final event = confirm();
      final s = _apply([ToolCallStarted(_call), event]);
      final q = s.pending! as ToolQuestion;
      expect(q.event, same(event));
      expect(q.request, 'Hallo');
      expect(_tool(s).phase, ToolPhase.awaitingConfirmation);
    });

    test('ToolCallFinished des Calls schließt die Frage', () {
      final s = _apply([
        ToolCallStarted(_call),
        confirm(),
        ToolCallFinished(call: _call, outcome: ToolOutcome.declined()),
      ]);
      expect(s.pending, isNull);
    });

    test('ToolCallFinished eines anderen Calls lässt die Frage offen', () {
      final other = ToolCallBlock(id: 'c2', name: 'x__y', argumentsJson: '{}');
      final s = _apply([
        ToolCallStarted(_call),
        ToolCallStarted(other),
        confirm(),
        ToolCallFinished(call: other, outcome: ToolOutcome.text('ok')),
      ]);
      expect(s.pending, isA<ToolQuestion>());
    });

    test('EscalationConfirmationRequired fragt mit Anzeigenamen', () {
      final s = _apply([
        EscalationConfirmationRequired(
          fromProfile: 'phala',
          toProfile: 'sonnet',
          reason: EscalationReason.userRequested,
          respond: (_) {},
        ),
      ]);
      final q = s.pending! as EscalationQuestion;
      expect(q.fromName, 'Phala · GLM klein');
      expect(q.toName, 'Claude Sonnet');
    });

    test('answered schließt die Frage', () {
      final s = reducer.answered(_apply([ToolCallStarted(_call), confirm()]));
      expect(s.pending, isNull);
    });
  });

  test('Escalated zeigt den Trenner und wechselt den aktiven Provider', () {
    final s = _apply([
      const AgentTextDelta('Kann ich nicht'),
      const Escalated(
        fromProfile: 'phala',
        toProfile: 'sonnet',
        reason: EscalationReason.userRequested,
      ),
      const AgentTextReset('Übergabe'),
      const AgentTextDelta('Fünf Punkte'),
    ]);
    expect(
      s.entries.whereType<EscalationEntry>().single.label,
      'an Claude Sonnet übergeben',
    );
    expect(s.activeProfileId, 'sonnet');
    // Escalated beendet den Abschnitt nicht: der Reset danach verwirft die
    // ersetzte Antwort (ADR 0003 §4).
    expect(_texts(s), ['Fünf Punkte']);
  });

  test('Text nach Escalated ohne Reset beginnt hinter dem Trenner', () {
    final s = _apply([
      const AgentTextDelta('Alt'),
      const Escalated(
        fromProfile: 'phala',
        toProfile: 'sonnet',
        reason: EscalationReason.userRequested,
      ),
      const AgentTextDelta('Neu'),
    ]);
    expect(s.entries.map((e) => e.runtimeType), [
      UserEntry,
      AssistantTextEntry,
      EscalationEntry,
      AssistantTextEntry,
    ]);
    expect(_texts(s), ['Alt', 'Neu']);
  });

  test('UsageReported ändert den Zustand nicht', () {
    final before = _apply([const AgentTextDelta('x')]);
    final after = _apply([
      const UsageReported(profileId: 'p', modelId: 'm', usage: Usage.zero),
    ], before);
    expect(identical(after, before), isTrue);
  });

  test('Verification des antwortenden Profils merkt sich den Prüfstatus', () {
    final routed = _apply([
      const Routed(profileId: 'p', modelId: 'm', reason: 'Standard'),
    ]);
    final checked = _apply([
      const Verification(profileId: 'p', status: VerificationStatus.verified),
    ], routed);
    expect(checked.verification, VerificationStatus.verified);
    // Prüfung eines anderen Profils betrifft den Kopf nicht.
    final other = _apply([
      const Verification(profileId: 'q', status: VerificationStatus.failed),
    ], checked);
    expect(other.verification, VerificationStatus.verified);
    // Neues Routing: alter Status gilt nicht mehr.
    final next = _apply([
      const Routed(profileId: 'q', modelId: 'm', reason: 'Standard'),
    ], other);
    expect(next.verification, isNull);
  });

  group('Ende des Laufs', () {
    test('AgentDone beendet den Lauf und schließt Fragen', () {
      final s = _apply([
        const AgentTextDelta('Fertig'),
        const AgentDone(finalText: 'Fertig', stopReason: StopReason.endTurn),
      ]);
      expect(s.running, isFalse);
      expect(s.pending, isNull);
      expect(_texts(s), ['Fertig']);
    });

    test('AgentDone ohne gestreamten Text zeigt den Endtext', () {
      final s = _apply([
        const AgentDone(
          finalText: 'Nur am Ende',
          stopReason: StopReason.endTurn,
        ),
      ]);
      expect(_texts(s), ['Nur am Ende']);
    });

    test('AgentFailed zeigt die Meldung als Fehler', () {
      final s = _apply([
        const AgentFailed(error: AgentErrorKind.timeout, message: 'Zu langsam'),
      ]);
      final n = s.entries.whereType<NoticeEntry>().single;
      expect(n.kind, NoticeKind.error);
      expect(n.text, 'Zu langsam');
      expect(s.running, isFalse);
    });

    test('Abbruch ist ein neutraler Hinweis', () {
      final s = _apply([
        const AgentFailed(error: AgentErrorKind.cancelled, message: 'x'),
      ]);
      final n = s.entries.whereType<NoticeEntry>().single;
      expect(n.kind, NoticeKind.info);
      expect(n.text, 'Abgebrochen.');
    });
  });

  group('Undo-Updates', () {
    ConversationState withUndo() => _apply([
      ToolCallStarted(_call),
      ToolCallFinished(
        call: _call,
        outcome: ToolOutcome.text(
          'ok',
          undo: UndoAction(label: 'weg', run: () async {}),
        ),
      ),
    ]);

    UndoUpdate update(UndoState state, int ms) => UndoUpdate(
      callId: 'c1',
      label: 'weg',
      state: state,
      remaining: Duration(milliseconds: ms),
    );

    test('Countdown, rückgängig und abgelaufen', () {
      var s = reducer.undo(withUndo(), update(UndoState.pending, 7000));
      expect(_tool(s).undoRemaining, const Duration(seconds: 7));
      s = reducer.undo(s, update(UndoState.undone, 0));
      expect(_tool(s).undo, UndoPhase.undone);
      expect(
        reducer.undo(withUndo(), update(UndoState.expired, 0)),
        isA<ConversationState>().having(
          (x) => _tool(x).undo,
          'undo',
          UndoPhase.expired,
        ),
      );
      expect(
        _tool(reducer.undo(withUndo(), update(UndoState.failed, 0))).undo,
        UndoPhase.failed,
      );
    });

    test('später Tick belebt ein laufendes Undo nicht wieder', () {
      var s = reducer.undoStarted(withUndo(), 'c1');
      expect(_tool(s).undo, UndoPhase.running);
      s = reducer.undo(s, update(UndoState.pending, 3000));
      expect(_tool(s).undo, UndoPhase.running);
    });
  });

  test('notice hängt einen Hinweis an', () {
    final s = reducer.notice(ConversationState.empty, NoticeKind.info, 'Hi');
    expect((s.entries.single as NoticeEntry).text, 'Hi');
  });

  group('AttestationStatusChanged (WP52)', () {
    AttestationStatusChanged status(
      AttestationStatus st, {
      String step = 's:1',
      String logId = 'l1',
      String? reason,
    }) => AttestationStatusChanged(
      stepId: step,
      status: st,
      logId: logId,
      detail: 'Hinweis',
      reasonCode: reason,
    );

    AnswerAttestation? shield(ConversationState s, [int i = 0]) =>
        s.entries.whereType<AssistantTextEntry>().elementAt(i).attestation;

    test('setzt den Status an der Antwort dieses Schritts', () {
      final s = _apply([
        const AgentTextDelta('Antwort'),
        status(AttestationStatus.green, reason: null),
      ]);
      expect(shield(s)?.status, AttestationStatus.green);
      expect(shield(s)?.logId, 'l1');
      expect(shield(s)?.stepId, 's:1');
    });

    test('Zwischenstand gelb wird zu grün oder rot (gleicher Schritt)', () {
      final yellow = _apply([
        const AgentTextDelta('Antwort'),
        status(AttestationStatus.yellow, logId: ''),
      ]);
      expect(shield(yellow)?.status, AttestationStatus.yellow);
      expect(shield(yellow)?.logId, isEmpty);
      final green = _apply([status(AttestationStatus.green)], yellow);
      expect(shield(green)?.status, AttestationStatus.green);
      final red = _apply([
        status(AttestationStatus.red, reason: 'upstream_tcb_out_of_date'),
      ], yellow);
      expect(shield(red)?.status, AttestationStatus.red);
      expect(shield(red)?.reasonCode, 'upstream_tcb_out_of_date');
      expect(
        red.entries.whereType<AssistantTextEntry>(),
        hasLength(1),
        reason: 'kein zweiter Eintrag',
      );
    });

    test('kommt nach dem Ende der Antwort (AgentDone), landet er richtig', () {
      final s = _apply([
        const AgentTextDelta('Antwort'),
        const AgentDone(finalText: 'Antwort', stopReason: StopReason.endTurn),
        status(AttestationStatus.red),
      ]);
      expect(s.running, isFalse);
      expect(shield(s)?.status, AttestationStatus.red);
      expect(s.entries.whereType<AssistantTextEntry>(), hasLength(1));
    });

    test('zwei Modellaufrufe: jeder Status an seinem Text', () {
      final s = _apply([
        const AgentTextDelta('Ich schaue nach.'),
        status(AttestationStatus.green, step: 's:1', logId: 'l1'),
        ToolCallStarted(_call),
        const AgentTextDelta('Fertig.'),
        status(AttestationStatus.red, step: 's:2', logId: 'l2'),
      ]);
      final texts = s.entries.whereType<AssistantTextEntry>().toList();
      expect(texts, hasLength(2));
      expect(texts[0].attestation?.status, AttestationStatus.green);
      expect(texts[0].attestation?.stepId, 's:1');
      expect(texts[1].attestation?.status, AttestationStatus.red);
      expect(texts[1].attestation?.stepId, 's:2');
    });

    test('Aufruf ohne Text: Status geht nicht an die vorige Antwort', () {
      final s = _apply([
        const AgentTextDelta('Erste Antwort'),
        status(AttestationStatus.green, step: 's:1'),
        status(AttestationStatus.green, step: 's:2', logId: 'l2'),
      ]);
      expect(shield(s)?.stepId, 's:1');
    });

    test('rotes Ergebnis ohne Antworttext bleibt als Hinweis sichtbar', () {
      final s = _apply([status(AttestationStatus.red)]);
      final notice = s.entries.whereType<NoticeEntry>().single;
      expect(notice.kind, NoticeKind.error);
    });

    test('spätes GPU-Ergebnis färbt die letzte geprüfte Antwort rot', () {
      final s = _apply([
        const AgentTextDelta('Antwort'),
        status(AttestationStatus.green),
      ]);
      final late = reducer.lateFailure(
        s,
        const AttestationReport(
          logId: 'g1',
          status: AttestationStatus.red,
          detail: 'GPU-Prüfung: abgelehnt',
          reasonCode: 'gpu_failed',
        ),
        text: 'GPU-Prüfung fehlgeschlagen',
      );
      expect(shield(late)?.status, AttestationStatus.red);
      expect(shield(late)?.reasonCode, 'gpu_failed');
      expect(shield(late)?.logId, 'g1');
      final none = reducer.lateFailure(
        ConversationState.empty,
        const AttestationReport(logId: 'g', status: AttestationStatus.red),
        text: 'Hinweis',
      );
      expect(none.entries.single, isA<NoticeEntry>());
    });
  });
}
