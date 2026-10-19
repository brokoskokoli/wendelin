import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/design/gallery.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin/ui/screens/main_parts.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';

export '../ui/helpers.dart' show pumpUntil;

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
}

Future<void> pumpApp(WidgetTester tester, TestEnv env) async {
  setView(tester, screenSize);
  await tester.pumpWidget(env.app());
  await tester.pump();
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MainScreen, skipOffstage: false)),
);

void main() {
  testWidgets(
    'Text senden → Fake-Provider → Tool-Karte mit Rückgängig → Antwort; '
    'Undo ruft den Port',
    (tester) async {
      final env = TestEnv(demo: true);
      await pumpApp(tester, env);
      expect(find.text('Demo · Skript'), findsOneWidget);

      await send(tester, 'Trag mir morgen um 10 Tauchen ein');
      expect(find.text('Trag mir morgen um 10 Tauchen ein'), findsOneWidget);
      await pumpUntil(tester, find.textContaining('steht im Kalender'));

      final card = find.byType(ToolResultCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Termin angelegt')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('Tauchen')),
        findsOneWidget,
      );
      expect(find.text('calendar__create_event'), findsOneWidget);
      expect(env.calendar.events.single.title, 'Tauchen');
      expect(
        env.calendar.events.single.start,
        DateTime.utc(2026, 10, 14, 8),
        reason: '14.10. 10:00 Berlin',
      );

      final undo = find.textContaining('Rückgängig · ');
      expect(undo, findsOneWidget);
      await tester.tap(undo);
      await tester.pump();
      await tester.pump();
      expect(env.calendar.events, isEmpty);
      expect(env.calendar.methodCalls, contains('deleteEvent'));
      expect(find.text('Rückgängig gemacht'), findsOneWidget);
      expect(find.textContaining('Rückgängig · '), findsNothing);
    },
  );

  testWidgets('Rückgängig läuft nach 10 s ab', (tester) async {
    final env = TestEnv(demo: true);
    await pumpApp(tester, env);
    await send(tester, 'Trag mir morgen um 10 Tauchen ein');
    await pumpUntil(tester, find.textContaining('steht im Kalender'));
    expect(find.textContaining('Rückgängig · 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('Rückgängig · '), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(find.textContaining('Rückgängig'), findsNothing);
    expect(find.byType(ToolResultCard), findsNothing);
    expect(find.byType(ToolChip), findsOneWidget);
    expect(env.calendar.events, hasLength(1), reason: 'bleibt bestehen');
  });

  testWidgets('Rückgängig: nach 9,9 s noch da, nach 10 s weg', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call(
              'c1',
              'calendar__create_event',
              '{"title":"Tauchen","start":"2026-10-14T10:00"}',
            ),
          ]),
          ScriptedTurn.text('Erledigt.'),
        ]),
      ),
    );
    await pumpApp(tester, env);
    await send(tester, 'Trag mir morgen um 10 Tauchen ein');
    // Ohne Verzögerung im Skript: alles läuft im selben Augenblick, das
    // Undo-Fenster beginnt bei 0.
    await tester.pump();
    await tester.pump();
    expect(find.text('Erledigt.'), findsOneWidget);
    expect(find.textContaining('Rückgängig · '), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 9900));
    expect(find.textContaining('Rückgängig · '), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.textContaining('Rückgängig'), findsNothing);
    expect(find.byType(ToolResultCard), findsNothing);
  });

  testWidgets('external-Tool → Bestätigungs-Sheet; „Nein“ → nicht ausgeführt', (
    tester,
  ) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Gut, der Termin bleibt.'),
        ]),
      ),
    );
    await env.calendar.createEvent(zahnarztDraft());
    env.calendar.methodCalls.clear();
    await pumpApp(tester, env);

    await send(tester, 'Lösch den Zahnarzttermin am Donnerstag.');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await tester.pumpAndSettle();
    expect(find.text('Termin löschen?'), findsOneWidget);
    expect(
      find.text('„Lösch den Zahnarzttermin am Donnerstag.“'),
      findsOneWidget,
    );
    expect(
      find.text('calendar__delete_event · Stufe external'),
      findsOneWidget,
    );
    expect(env.calendar.methodCalls, isNot(contains('deleteEvent')));

    await tester.tap(find.text('Nein, behalten'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Gut, der Termin bleibt.'));
    expect(find.byType(ConfirmationSheet), findsNothing);
    expect(env.calendar.methodCalls, isNot(contains('deleteEvent')));
    expect(env.calendar.events, hasLength(1));
    final chip = tester.widget<ToolChip>(find.byType(ToolChip));
    expect(chip.status, CheckStatus.failed);
  });

  testWidgets('verschärftes write-Tool zeigt Stufe external', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call(
              'c1',
              'calendar__create_event',
              '{"title":"Tauchen","start":"2026-10-15T10:00"}',
            ),
          ]),
          ScriptedTurn.text('Gut, nicht eingetragen.'),
        ]),
      ),
    );
    await pumpApp(tester, env);
    containerOf(tester)
        .read(riskPolicyProvider)
        .setOverride('calendar__create_event', PolicyAction.confirm);

    await send(tester, 'Trag Tauchen ein');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await tester.pumpAndSettle();
    expect(
      find.text('calendar__create_event · Stufe external'),
      findsOneWidget,
    );
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Gut, nicht eingetragen.'));
    expect(env.calendar.methodCalls, isNot(contains('createEvent')));
  });

  testWidgets('„Ja“ im Sheet führt das Tool aus', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Gelöscht.'),
        ]),
      ),
    );
    await env.calendar.createEvent(zahnarztDraft());
    await pumpApp(tester, env);
    await send(tester, 'Lösch den Zahnarzttermin');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ja, löschen'));
    await pumpUntil(tester, find.text('Gelöscht.'));
    expect(env.calendar.events, isEmpty);
  });

  testWidgets('Sheet wegwischen gilt als „Nein“', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Abgelehnt.'),
        ]),
      ),
    );
    await env.calendar.createEvent(zahnarztDraft());
    await pumpApp(tester, env);
    await send(tester, 'Lösch den Zahnarzttermin');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 40));
    await pumpUntil(tester, find.text('Abgelehnt.'));
    expect(env.calendar.events, hasLength(1));
  });

  testWidgets('Abbruch während der Frage schließt das Sheet', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
        ]),
      ),
    );
    await env.calendar.createEvent(zahnarztDraft());
    await pumpApp(tester, env);
    await send(tester, 'Lösch den Zahnarzttermin');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await tester.pumpAndSettle();
    containerOf(tester).read(agentControllerProvider.notifier).cancel();
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmationSheet), findsNothing);
    expect(find.text('Abgebrochen.'), findsOneWidget);
    expect(env.calendar.events, hasLength(1));
  });

  testWidgets('Antwort wird live gestreamt', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.text('Ruhig: 0,4 m Welle, Wasser 19 °C.', chunkSize: 6),
        ], eventDelay: const Duration(milliseconds: 100)),
      ),
    );
    await pumpApp(tester, env);
    await send(tester, 'Wie wird das Meer?');
    await pumpUntil(tester, find.text('Ruhig:'));
    expect(find.text('Ruhig: 0,4 m Welle, Wasser 19 °C.'), findsNothing);
    await pumpUntil(tester, find.text('Ruhig: 0,4 m Welle, Wasser 19 °C.'));
  });

  testWidgets(
    'Mikrofon: ohne Spracherkennung aus, im Lauf „Antwort abbrechen“',
    (tester) async {
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.hang(partialText: 'Moment')]),
        ),
      );
      await pumpApp(tester, env);
      final mic = tester.widget<MicButton>(find.byType(MicButton));
      expect(mic.state, MicState.disabled);
      expect(
        find.byTooltip(AppLocalizationsDe().voiceUnavailableHint),
        findsOneWidget,
      );

      await send(tester, 'Hallo');
      await pumpUntil(tester, find.text('Moment'));
      expect(
        tester.widget<MicButton>(find.byType(MicButton)).state,
        MicState.thinking,
      );
      await tester.tap(find.byType(MicButton));
      await pumpUntil(tester, find.text('Abgebrochen.'));
      expect(
        tester.widget<MicButton>(find.byType(MicButton)).state,
        MicState.disabled,
      );
    },
  );

  testWidgets('ohne Provider: Hinweis-Karte, „Provider einrichten“ öffnet '
      'die Einrichtung', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env);
    await tester.pumpAndSettle();
    expect(find.byType(ProviderSetupCard), findsOneWidget);
    expect(find.byType(ProviderChip), findsNothing);
    await tester.tap(find.text('Provider einrichten'));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderSetupScreen), findsOneWidget);
  });

  testWidgets('ohne Provider: Demo starten (Debug)', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo ohne Provider starten'));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderSetupCard), findsNothing);
    expect(find.text('Demo · Skript'), findsOneWidget);
  });

  testWidgets('kaputtes Profil: Hinweis „Provider prüfen“', (tester) async {
    final env = TestEnv(providerConfigError: ArgumentError('Base-URL fehlt'));
    await pumpApp(tester, env);
    await tester.pumpAndSettle();
    expect(find.text('Provider prüfen'), findsOneWidget);
    expect(find.textContaining('Base-URL fehlt'), findsOneWidget);
  });

  testWidgets('Stationsmodus: Button im Kopf startet die Station', (
    tester,
  ) async {
    final env = TestEnv();
    await pumpApp(tester, env);
    expect(env.station.starts, 0);
    await tester.tap(find.byTooltip('Stationsmodus starten'));
    await tester.pump();
    expect(env.station.starts, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('Einstellungen öffnen und zurück', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env);
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
  });

  testWidgets('Einstellungen (Debug): Demo-Schalter und Galerie', (
    tester,
  ) async {
    final env = TestEnv();
    await pumpApp(tester, env);
    await tester.tap(find.byTooltip('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Design-Galerie'), 100);
    await tester.ensureVisible(find.byType(WSwitch).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WSwitch).last);
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(demoModeProvider), isTrue);
    await tester.tap(find.text('Design-Galerie'));
    // Die Galerie zeigt die bewegten Punkte (Sprechen): kein Settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DesignGallery), findsOneWidget);
  });

  testWidgets('Kosten-Chip zeigt die Kosten von heute', (tester) async {
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    await env.storage.usage.record(
      sessionId: 's',
      profileId: 'claude',
      modelId: 'claude-haiku-4-5',
      usage: Usage.zero,
      costMicros: 30000,
    );
    await pumpApp(tester, env);
    await tester.pumpAndSettle();
    expect(find.text('heute 0,03 \$'), findsOneWidget);
    expect(find.text('Claude Haiku'), findsOneWidget);
  });
}
