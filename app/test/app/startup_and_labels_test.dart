import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/main.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/conversation_view.dart';
import 'package:wendelin/ui/screens/labels.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';

const _tz = MethodChannel('flutter_timezone');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadDeviceInfo', () {
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_tz, null),
    );

    test('IANA-Zone vom Gerät', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_tz, (_) async => 'Europe/Paris');
      final info = await loadDeviceInfo();
      expect(info.timeZone, 'Europe/Paris');
      expect(info.locale, isNotEmpty);
    });

    test('ohne Zone vom Gerät: UTC', () async {
      for (final handler in <Future<Object?> Function(MethodCall)?>[
        (_) async => throw PlatformException(code: 'x'),
        (_) async => null,
        null,
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_tz, handler);
        expect((await loadDeviceInfo()).timeZone, 'UTC');
      }
    });
  });

  group('Texte', () {
    test('Sitzungsmarke: heute, gestern, Datum', () {
      final now = DateTime(2026, 10, 13, 20);
      expect(sessionLabel(DateTime(2026, 10, 13, 8, 5), now), 'Heute · 08:05');
      expect(
        sessionLabel(DateTime(2026, 10, 12, 23, 59), now),
        'Gestern · 23:59',
      );
      expect(sessionLabel(DateTime(2026, 10, 2, 7), now), '02.10. · 07:00');
    });

    test('Bestätigungstexte je Tool', () {
      expect(
        confirmationTexts('calendar__delete_event').title,
        'Termin löschen?',
      );
      final clear = confirmationTexts('lists__clear_completed');
      expect(clear.title, 'Wirklich löschen?');
      expect(clear.yes, 'Ja, löschen');
      expect(clear.no, 'Nein, behalten');
      final other = confirmationTexts('sms__send');
      expect(other.title, 'Soll ich das tun?');
      expect(other.yes, 'Ja, ausführen');
      expect(other.no, 'Nein');
      // „delete“ im Integrationsnamen zählt nicht.
      expect(confirmationTexts('delete__send').title, 'Soll ich das tun?');
    });

    test('Kurztext wird am ersten „: “ geteilt', () {
      expect(splitSummary('Termin angelegt: Tauchen, Di 10:00', 'x'), (
        'Termin angelegt',
        'Tauchen, Di 10:00',
      ));
      expect(splitSummary('Kopiert', 'x'), ('Kopiert', ''));
      expect(splitSummary(null, 'calendar__x'), ('calendar__x', ''));
    });

    test('Icons je Integration', () {
      expect(integrationIcon('calendar'), WIcons.calendar);
      expect(integrationIcon('memory'), WIcons.note);
      expect(integrationIcon('lists'), WIcons.cart);
      expect(integrationIcon('web'), WIcons.globe);
      expect(integrationIcon('clipboard'), WIcons.clipboard);
      expect(integrationIcon('flashlight'), WIcons.flashlight);
      expect(integrationIcon('alarms'), WIcons.alarm);
      expect(integrationIcon('irgendwas'), WIcons.task);
    });
  });

  group('Verlaufsanzeige', () {
    Future<void> pump(
      WidgetTester tester,
      List<ChatEntry> entries, {
      bool showThinking = false,
    }) async {
      setView(tester, screenSize);
      await tester.pumpWidget(
        themed(
          ConversationView(
            entries: entries,
            now: testNow,
            onUndo: (_) {},
            showThinking: showThinking,
          ),
        ),
      );
    }

    const entries = [
      UserEntry('u', 'Frage'),
      ThinkingEntry('t', 'Ich überlege'),
      AssistantTextEntry('a', 'Antwort'),
      NoticeEntry('n1', NoticeKind.warning, 'Budget fast leer'),
      NoticeEntry('n2', NoticeKind.error, 'Fehlgeschlagen'),
      NoticeEntry('n3', NoticeKind.providerData, 'Websuche: Nizza'),
    ];

    testWidgets('Thinking nur auf Wunsch', (tester) async {
      await pump(tester, entries);
      expect(find.text('Ich überlege'), findsNothing);
      await pump(tester, entries, showThinking: true);
      expect(find.text('Ich überlege'), findsOneWidget);
    });

    testWidgets('Hinweise mit Statusform je Art', (tester) async {
      await pump(tester, entries);
      final icons = tester
          .widgetList<CheckStatusIcon>(find.byType(CheckStatusIcon))
          .map((i) => i.status)
          .toList();
      expect(icons, [CheckStatus.pending, CheckStatus.failed]);
      expect(find.text('Websuche: Nizza'), findsOneWidget);
    });

    testWidgets('Tool-Chips: Formen nach Ergebnis', (tester) async {
      await pump(tester, const [
        ToolEntry('1', toolName: 'a__b'),
        ToolEntry('2', toolName: 'a__c', phase: ToolPhase.done),
        ToolEntry('3', toolName: 'a__d', phase: ToolPhase.declined),
        ToolEntry('4', toolName: 'a__e', phase: ToolPhase.failed),
        AssistantTextEntry('x', 'Fertig'),
      ]);
      expect(
        tester.widgetList<ToolChip>(find.byType(ToolChip)).map((c) => c.status),
        [
          CheckStatus.pending,
          CheckStatus.ok,
          CheckStatus.failed,
          CheckStatus.failed,
        ],
      );
    });
  });

  test(
    'Kalender: Bestätigungstext live nachgeschlagen, kein Cache (WP14)',
    () async {
      final port = FakeCalendarPort();
      final deps = IntegrationDeps(
        ports: PlatformPorts(
          calendar: port,
          clipboard: FakeClipboardPort(),
          alarms: FakeAlarmPort(),
          memory: FakeMemoryStore(),
          apps: FakeAppPresencePort(),
          torch: FakeTorchPort(),
        ),
        device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
        httpClient: http.Client(),
      );
      final spec = builtInIntegrationSpecs.firstWhere(
        (s) => s.id == 'calendar',
      );
      final calendar = spec.create(deps) as CalendarIntegration;
      final ctx = ToolContext(
        sessionId: 's',
        clock: FixedClock(testNow),
        locale: 'de-DE',
        timeZone: 'Europe/Berlin',
      );
      Tool tool(String name) =>
          calendar.tools.firstWhere((t) => t.name == name);
      final created = await tool('calendar__create_event')
          .execute({'title': 'Tauchen', 'start': '2026-10-14T10:00'}, ctx);
      expect(created.isError, isFalse);
      final id = port.events.single.id;
      final delete = tool('calendar__delete_event');
      // Synchron nur die Id, vor der Frage schlägt das Tool den Termin nach.
      expect(delete.describeForConfirmation({'event_id': id}), contains(id));
      expect(
        await delete.confirmationText({'event_id': id}, ctx),
        contains('Tauchen'),
      );
      // Kein Cache mehr, also auch kein Aufräumen am Sitzungsende.
      expect(spec.onSessionEnd, isNull);
    },
  );
}
