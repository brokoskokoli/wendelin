import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

MediaSnapshot _book({bool playing = true, int? pos = 600000, int? dur}) =>
    MediaSnapshot(
      packageName: audiblePackage,
      appName: 'Audible',
      playing: playing,
      title: 'Der Process',
      artist: 'Franz Kafka',
      positionMs: pos,
      durationMs: dur ?? 3600000,
    );

void main() {
  late FakeMediaControlPort port;
  late FakeAppPresencePort apps;
  late MediaIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(
    String name, [
    Map<String, Object?> args = const {},
  ]) => tool(name).execute(args, ctx());

  setUp(() {
    port = FakeMediaControlPort(snapshot: _book());
    apps = FakeAppPresencePort(installed: [audiblePackage]);
    integration = MediaIntegration(port, apps);
  });

  test('Metadaten, Risiken, Vertrauenseinstufung', () async {
    expect(integration.id, 'media');
    expect(integration.sensitive, isTrue);
    expect(integration.platforms, {AppPlatform.android});
    expect(await integration.checkAvailability(), Availability.yes);
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {
        'media__now_playing': RiskLevel.read,
        'media__play': RiskLevel.write,
        'media__pause': RiskLevel.write,
        'media__next': RiskLevel.write,
        'media__previous': RiskLevel.write,
        'media__seek': RiskLevel.write,
        'media__open_audible': RiskLevel.write,
      },
    );
    expect(tool('media__now_playing'), isA<TrustedContentSource>());
    expect(tool('media__pause'), isA<TrustedContentSource>());
  });

  test('Einrichtung: Zugriff fehlt = optionaler Schritt offen', () async {
    expect((await integration.setupState()).missingSteps, isEmpty);
    port.access = false;
    final state = await integration.setupState();
    expect(state.missingSteps, [MediaIntegration.accessStep]);
    expect(state.requiredComplete(integration.setup), isTrue);
  });

  test('now_playing: App, Titel, Position als Text', () async {
    final o = await run('media__now_playing');
    expect(o.isError, isFalse);
    expect(json(o), {
      'app': 'Audible',
      'playing': true,
      'title': 'Der Process',
      'artist': 'Franz Kafka',
      'position': '10:00',
      'duration': '1:00:00',
    });
    expect(o.summary, 'Läuft: Der Process (Audible)');
  });

  test('now_playing: nichts aktiv, und ohne Zugriff ein Fehler', () async {
    port.snapshot = null;
    final o = await run('media__now_playing');
    expect(o.isError, isFalse);
    expect(o.text, contains('läuft nichts'));
    port.access = false;
    final err = await run('media__now_playing');
    expect(err.isError, isTrue);
    expect(err.text, contains('Benachrichtigungszugriff'));
  });

  test('pause: sendet pause, Undo spielt wieder ab', () async {
    final o = await run('media__pause');
    expect(port.sent, [MediaCommand.pause]);
    expect(o.undo!.label, 'Wieder abspielen');
    await o.undo!.run();
    expect(port.sent, [MediaCommand.pause, MediaCommand.play]);
    expect(port.snapshot!.playing, isTrue);
  });

  test('play: pausiert -> spielt, Undo pausiert', () async {
    port.snapshot = _book(playing: false);
    final o = await run('media__play');
    expect(port.sent, [MediaCommand.play]);
    await o.undo!.run();
    expect(port.sent.last, MediaCommand.pause);
  });

  test('play bei laufender Wiedergabe: nichts senden, kein Undo', () async {
    final o = await run('media__play');
    expect(port.sent, isEmpty);
    expect(o.undo, isNull);
    expect(o.text, 'Es läuft schon.');
  });

  test(
    'Medientasten-Fallback ohne Zugriff: sendet trotzdem, Undo da',
    () async {
      port.access = false;
      final o = await run('media__pause');
      expect(o.isError, isFalse);
      expect(port.sent, [MediaCommand.pause]);
      expect(o.undo, isNotNull);
      // Unknown effect: "sent", not "is paused"; undo says what it does.
      expect(o.text, 'Pause gesendet.');
      expect(o.undo!.label, 'Abspielen senden');
      final p = await run('media__play');
      expect(p.text, 'Abspielen gesendet.');
      expect(p.undo!.label, 'Pause senden');
    },
  );

  test('next/previous: senden, kein Undo, kein Titel im Ergebnis', () async {
    for (final n in ['media__next', 'media__previous']) {
      final o = await run(n);
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
      expect(o.text, isNot(contains('Process')));
    }
    expect(port.sent, [MediaCommand.next, MediaCommand.previous]);
  });

  test('seek relativ: 30 s zurück, Undo springt zurück', () async {
    final o = await run('media__seek', {'seconds': -30});
    expect(port.seeks, [const Duration(minutes: 9, seconds: 30)]);
    expect(o.text, 'Position jetzt 9:30.');
    await o.undo!.run();
    expect(port.seeks.last, const Duration(minutes: 10));
  });

  test('seek: klemmt auf 0 und auf die Länge', () async {
    await run('media__seek', {'seconds': -40000});
    expect(port.seeks.last, Duration.zero);
    await run('media__seek', {'seconds': 40000});
    // One second before the end, not exactly the end.
    expect(port.seeks.last, const Duration(minutes: 59, seconds: 59));
  });

  test('seek: sehr kurzer Titel klemmt auf 0', () async {
    port.snapshot = _book(dur: 800);
    await run('media__seek', {'seconds': 100});
    expect(port.seeks.last, Duration.zero);
  });

  test('now_playing: lange Texte werden auf 200 Zeichen gekürzt', () async {
    port.snapshot = MediaSnapshot(
      packageName: audiblePackage,
      appName: 'Audible',
      playing: true,
      title: 'T' * 300,
      artist: 'A' * 200,
      album: 'B' * 201,
    );
    final d = json(await run('media__now_playing'));
    expect(d['artist'], 'A' * 200);
    expect(d['album'], '${'B' * 199}…');
    expect((d['title'] as String).length, 200);
  });

  test('seek absolut', () async {
    await run('media__seek', {'position_seconds': 90});
    expect(port.seeks, [const Duration(seconds: 90)]);
  });

  test('seek: Argumente prüfen', () async {
    expect((await run('media__seek')).isError, isTrue);
    expect(
      (await run('media__seek', {'seconds': 1, 'position_seconds': 2})).isError,
      isTrue,
    );
    expect((await run('media__seek', {'seconds': 'x'})).isError, isTrue);
    expect(port.seeks, isEmpty);
  });

  test(
    'seek: ohne Player, ohne Zugriff, ohne Position, nicht spulbar',
    () async {
      port.snapshot = _book(pos: null);
      final noPos = await run('media__seek', {'seconds': 10});
      expect(noPos.isError, isTrue);
      expect(
        (await run('media__seek', {'position_seconds': 5})).isError,
        isFalse,
      );
      port.snapshot = null;
      expect((await run('media__seek', {'seconds': 10})).isError, isTrue);
      port.snapshot = _book();
      port.seekable = false;
      expect((await run('media__seek', {'seconds': 10})).isError, isTrue);
      port.access = false;
      final denied = await run('media__seek', {'seconds': 10});
      expect(denied.text, contains('Benachrichtigungszugriff'));
    },
  );

  test('open_audible: öffnet, mit Suchbegriff', () async {
    await run('media__open_audible');
    await run('media__open_audible', {'query': ' Kafka '});
    expect(port.opened, [audiblePackage, '$audiblePackage?Kafka']);
  });

  test(
    'open_audible: mit Suchbegriff sagt, dass direkt abgespielt wird',
    () async {
      final o = await run('media__open_audible', {'query': 'Kafka'});
      expect(o.text, contains('spielt direkt ab'));
      expect(
        tool('media__open_audible').description,
        contains('starts playing'),
      );
    },
  );

  test('open_audible: nicht installiert -> Fehler, nichts geöffnet', () async {
    apps.uninstall(audiblePackage);
    final o = await run('media__open_audible');
    expect(o.isError, isTrue);
    expect(o.text, 'Audible ist nicht installiert.');
    expect(port.opened, isEmpty);
  });

  test('Bestätigungstexte', () {
    String d(String n, [Map<String, Object?> a = const {}]) =>
        tool(n).describeForConfirmation(a);
    expect(d('media__pause'), 'Wiedergabe pausieren');
    expect(d('media__seek', {'seconds': -30}), '30 Sekunden zurückspulen');
    expect(d('media__seek', {'seconds': 45}), '45 Sekunden vorspulen');
    expect(
      d('media__seek', {'position_seconds': 3725}),
      'Springen auf 1:02:05',
    );
    expect(d('media__seek'), 'In der Wiedergabe spulen');
    expect(
      d('media__open_audible', {'query': 'Kafka'}),
      'Audible öffnen, „Kafka“ suchen und abspielen',
    );
    expect(d('media__open_audible'), 'Audible öffnen');
    expect(formatMediaTime(-5), '0:00');
  });

  mediaControlPortContract(
    () => FakeMediaControlPort(snapshot: _book()),
    name: 'FakeMediaControlPort',
  );
  mediaControlPortContract(
    () => FakeMediaControlPort(access: false),
    name: 'FakeMediaControlPort ohne Zugriff',
  );
  mediaControlPortContract(
    FakeMediaControlPort.new,
    name: 'FakeMediaControlPort ohne Player',
  );

  group('feste Bestätigung', () {
    test('pause, play, next, previous mit bekanntem Zustand', () async {
      expectFixed(
        await run('media__pause'),
        tool('media__pause'),
        'media.pause',
        de: 'Die Wiedergabe ist pausiert.',
      );
      expectFixed(
        await run('media__play'),
        tool('media__play'),
        'media.play',
        de: 'Die Wiedergabe läuft.',
      );
      expectFixed(await run('media__next'), tool('media__next'), 'media.next');
      expectFixed(
        await run('media__previous'),
        tool('media__previous'),
        'media.previous',
      );
    });

    test(
      'Medientasten ohne Zugriff: play/pause unbekannt → kein Satz',
      () async {
        port.access = false;
        for (final n in ['media__pause', 'media__play']) {
          final o = await run(n);
          expect(o.isError, isFalse);
          expect(o.fixed, isNull, reason: n);
        }
      },
    );

    test('Zustand schon erreicht → kein Satz', () async {
      final o = await run('media__play');
      expect(o.text, 'Es läuft schon.');
      expect(o.fixed, isNull);
    });
  });
}
