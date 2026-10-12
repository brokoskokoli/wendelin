import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

void main() {
  late WendelinStorage storage;
  late FixedClock clock;
  late ConversationRepository repo;

  setUp(() {
    final f = openTestStorage();
    storage = f.storage;
    clock = f.clock;
    repo = storage.conversations;
  });
  tearDown(() => storage.close());

  group('currentOrNew', () {
    test('legt ohne Sitzung eine neue an', () async {
      final s = await repo.currentOrNew(t0);
      expect(s.startedAt, t0);
      expect(s.lastActivityAt, t0);
      expect(await repo.sessions(), [s]);
    });

    test('liefert dieselbe Sitzung innerhalb von 5 min Inaktivität', () async {
      final s = await repo.currentOrNew(t0);
      final later = t0.add(const Duration(minutes: 4, seconds: 59));
      expect((await repo.currentOrNew(later)).id, s.id);
    });

    test('beginnt nach genau 5 min Inaktivität eine neue Sitzung', () async {
      final s = await repo.currentOrNew(t0);
      final next = await repo.currentOrNew(t0.add(const Duration(minutes: 5)));
      expect(next.id, isNot(s.id));
      expect(await repo.sessions(), hasLength(2));
    });

    test('misst die Inaktivität ab der letzten Nachricht', () async {
      final s = await repo.currentOrNew(t0);
      await repo.append(
        s.id,
        Message.user('hallo'),
        at: t0.add(const Duration(minutes: 4)),
      );
      final again = await repo.currentOrNew(t0.add(const Duration(minutes: 8)));
      expect(again.id, s.id);
    });

    test(
      'wählt die zuletzt aktive Sitzung und respektiert inactivity',
      () async {
        final a = await repo.startNew(t0);
        final b = await repo.startNew(t0.subtract(const Duration(hours: 1)));
        expect((await repo.currentOrNew(t0)).id, a.id);
        final custom = await repo.currentOrNew(
          t0.add(const Duration(minutes: 2)),
          inactivity: const Duration(minutes: 1),
        );
        expect(custom.id, isNot(anyOf(a.id, b.id)));
      },
    );
  });

  test('startNew, session, setTitle, sessions(limit)', () async {
    final a = await repo.startNew(t0, title: 'Tauchen');
    final b = await repo.startNew(t0.add(const Duration(hours: 1)));
    expect((await repo.session(a.id))!.title, 'Tauchen');
    expect(await repo.session('fehlt'), isNull);
    await repo.setTitle(b.id, 'Einkauf');
    await repo.setTitle(a.id, null);
    expect((await repo.session(b.id))!.title, 'Einkauf');
    expect((await repo.session(a.id))!.title, isNull);
    expect([for (final s in await repo.sessions()) s.id], [b.id, a.id]);
    expect([for (final s in await repo.sessions(limit: 1)) s.id], [b.id]);
  });

  group('append und messages', () {
    test('speichert alle Blocktypen verlustfrei über core-JSON', () async {
      final s = await repo.startNew(t0);
      final msgs = [
        Message.user(
          'Was ist auf dem Bild?',
          images: [
            ImageBlock(mediaType: 'image/png', bytes: [1, 2, 3, 255]),
          ],
        ),
        Message.assistant([
          const ThinkingBlock('Ich überlege', signature: 'sig=='),
          const ThinkingBlock.redacted('opaque-bytes'),
          const TextBlock('Ich schaue nach.'),
          const ToolCallBlock(
            id: 'call_1',
            name: 'calendar__list_events',
            argumentsJson: '{"day": "2026-10-14"}',
          ),
        ]),
        Message.toolResults([
          ToolResultBlock(
            callId: 'call_1',
            content: const [TextBlock('keine Termine')],
            isError: false,
          ),
        ]),
        Message.assistantText('Morgen ist frei.'),
      ];
      for (final m in msgs) {
        await repo.append(s.id, m, profileId: 'claude', modelId: 'haiku');
      }
      final stored = await repo.messages(s.id);
      expect([for (final m in stored) m.message], msgs);
      expect([for (final m in stored) m.seq], [1, 2, 3, 4]);
      expect(stored.first.profileId, 'claude');
      expect(stored.first.modelId, 'haiku');
      final thinking = stored[1].message.content[1] as ThinkingBlock;
      expect(thinking.redactedData, 'opaque-bytes');
      expect(
        (stored[1].message.content[0] as ThinkingBlock).signature,
        'sig==',
      );
    });

    test(
      'nutzt die Uhr als Standardzeit und aktualisiert lastActivityAt',
      () async {
        final s = await repo.startNew(t0);
        clock.advance(const Duration(minutes: 3));
        final m = await repo.append(s.id, Message.user('x'));
        expect(m.createdAt, clock.now());
        expect(m.profileId, isNull);
        expect((await repo.session(s.id))!.lastActivityAt, clock.now());
      },
    );

    test('Nummerierung ist je Sitzung unabhängig', () async {
      final a = await repo.startNew(t0);
      final b = await repo.startNew(t0);
      await repo.append(a.id, Message.user('a1'));
      await repo.append(b.id, Message.user('b1'));
      final a2 = await repo.append(a.id, Message.user('a2'));
      expect(a2.seq, 2);
      expect((await repo.messages(b.id)).single.seq, 1);
    });

    test(
      'unbekannte Sitzung wirft ArgumentError und speichert nichts',
      () async {
        await expectLater(
          repo.append('fehlt', Message.user('x')),
          throwsArgumentError,
        );
        expect(await repo.messages('fehlt'), isEmpty);
      },
    );
  });

  group('lastTurns', () {
    late String sid;
    setUp(() async {
      sid = (await repo.startNew(t0)).id;
      // Zug 1: einfache Antwort
      await repo.append(sid, Message.user('u1'));
      await repo.append(sid, Message.assistantText('a1'));
      // Zug 2: mit Tool-Runde
      await repo.append(sid, Message.user('u2'));
      await repo.append(
        sid,
        Message.assistant([
          const ToolCallBlock(id: 'c', name: 'x__y', argumentsJson: '{}'),
        ]),
      );
      await repo.append(
        sid,
        Message.toolResults([
          ToolResultBlock(callId: 'c', content: [], isError: false),
        ]),
      );
      await repo.append(sid, Message.assistantText('a2'));
      // Zug 3
      await repo.append(sid, Message.user('u3'));
      await repo.append(sid, Message.assistantText('a3'));
    });

    Future<List<int>> seqs(int n) async => [
      for (final m in await repo.lastTurns(sid, n)) m.seq,
    ];

    test('ein Zug: ab der letzten Nutzernachricht', () async {
      expect(await seqs(1), [7, 8]);
    });

    test('Tool-Aufruf und Ergebnis werden nie getrennt', () async {
      expect(await seqs(2), [3, 4, 5, 6, 7, 8]);
    });

    test('mehr Züge als vorhanden liefert alles', () async {
      expect(await seqs(3), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(await seqs(10), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('0 Züge oder fremde Sitzung liefert nichts', () async {
      expect(await seqs(0), isEmpty);
      expect(await repo.lastTurns('fehlt', 3), isEmpty);
    });
  });

  test('deleteSession löscht die Nachrichten mit', () async {
    final s = await repo.startNew(t0);
    await repo.append(s.id, Message.user('x'));
    await repo.deleteSession(s.id);
    expect(await repo.session(s.id), isNull);
    expect(await repo.messages(s.id), isEmpty);
  });

  test(
    'purgeOlderThan löscht nur Sitzungen mit alter letzter Aktivität',
    () async {
      final old = await repo.startNew(t0.subtract(const Duration(days: 31)));
      await repo.append(
        old.id,
        Message.user('alt'),
        at: t0.subtract(const Duration(days: 31)),
      );
      final edge = await repo.startNew(t0.subtract(const Duration(days: 30)));
      final recent = await repo.startNew(t0.subtract(const Duration(days: 2)));
      // Vor 60 Tagen begonnen, aber gestern noch aktiv: bleibt.
      final longRunning = await repo.startNew(
        t0.subtract(const Duration(days: 60)),
      );
      await repo.append(
        longRunning.id,
        Message.user('noch da'),
        at: t0.subtract(const Duration(days: 1)),
      );
      expect(await repo.purgeOlderThan(const Duration(days: 30)), 1);
      expect(await repo.session(longRunning.id), isNotNull);
      expect(await repo.session(old.id), isNull);
      expect(await repo.messages(old.id), isEmpty);
      expect(await repo.session(edge.id), isNotNull);
      expect(await repo.session(recent.id), isNotNull);
    },
  );
}
