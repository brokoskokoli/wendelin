import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_media_control_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Stands in for `MediaChannel.kt`: one player, access or not, errors.
final class _FakeMediaChannel {
  bool access = true;
  Map<String, Object?>? session = {
    'package': 'com.audible.application',
    'app': 'Audible',
    'playing': true,
    'title': 'Buch',
    'artist': null,
    'positionMs': 5000,
    'durationMs': 90000,
  };
  String? errorCode;
  final List<MethodCall> calls = [];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (errorCode case final code?) throw PlatformException(code: code);
    switch (call.method) {
      case 'hasSessionAccess':
        return access;
      case 'openSessionAccessSettings':
      case 'send':
        return null;
      case 'seekTo':
        if (session == null) throw PlatformException(code: 'no_session');
        return null;
      case 'nowPlaying':
        if (!access) throw PlatformException(code: 'no_access');
        return session;
      case 'openApp':
        final pkg = (call.arguments as Map)['package'];
        if (pkg != 'com.audible.application') {
          throw PlatformException(code: 'not_installed');
        }
        return null;
    }
    throw MissingPluginException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(mediaChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeMediaChannel platform;

  setUp(() {
    platform = _FakeMediaChannel();
    messenger.setMockMethodCallHandler(channel, platform.handle);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  mediaControlPortContract(
    () => const ChannelMediaControlPort(),
    name: 'ChannelMediaControlPort',
  );
  mediaControlPortContract(() {
    platform.access = false;
    return const ChannelMediaControlPort();
  }, name: 'ChannelMediaControlPort ohne Zugriff');
  mediaControlPortContract(() {
    platform.session = null;
    return const ChannelMediaControlPort();
  }, name: 'ChannelMediaControlPort ohne Player');

  test('nowPlaying liest die Map in einen MediaSnapshot', () async {
    final s = (await const ChannelMediaControlPort().nowPlaying())!;
    expect(s.appName, 'Audible');
    expect(s.title, 'Buch');
    expect(s.artist, isNull);
    expect(s.playing, isTrue);
    expect(s.positionMs, 5000);
    expect(s.durationMs, 90000);
  });

  test('nowPlaying: negative Zeiten (unbekannt) werden zu null', () async {
    platform.session = {
      ...platform.session!,
      'positionMs': -1,
      'durationMs': -1,
    };
    final s = (await const ChannelMediaControlPort().nowPlaying())!;
    expect(s.positionMs, isNull);
    expect(s.durationMs, isNull);
  });

  test('nowPlaying: Map ohne Paket gilt als kein Player', () async {
    platform.session = {'playing': true};
    expect(await const ChannelMediaControlPort().nowPlaying(), isNull);
  });

  test('Befehle und Sprung gehen mit ihren Argumenten raus', () async {
    const port = ChannelMediaControlPort();
    await port.send(MediaCommand.previous);
    await port.seekTo(const Duration(seconds: 90));
    await port.openApp('com.audible.application', searchQuery: 'Kafka');
    await port.openApp('com.audible.application');
    expect(platform.calls.map((c) => c.method), [
      'send',
      'seekTo',
      'openApp',
      'openApp',
    ]);
    expect(platform.calls[0].arguments, {'command': 'previous'});
    expect(platform.calls[1].arguments, {'positionMs': 90000});
    expect(platform.calls[2].arguments, {
      'package': 'com.audible.application',
      'query': 'Kafka',
    });
    expect(platform.calls[3].arguments, {'package': 'com.audible.application'});
  });

  test('Fehlercodes werden zu PortException-Arten', () async {
    const port = ChannelMediaControlPort();
    Future<PortErrorKind> kind(String code) async {
      platform.errorCode = code;
      try {
        await port.seekTo(Duration.zero);
      } on PortException catch (e) {
        return e.kind;
      }
      throw StateError('keine Ausnahme');
    }

    expect(await kind('no_access'), PortErrorKind.permissionDenied);
    expect(await kind('no_session'), PortErrorKind.notFound);
    expect(await kind('not_seekable'), PortErrorKind.unsupported);
    expect(await kind('not_installed'), PortErrorKind.notFound);
    expect(await kind('boom'), PortErrorKind.failed);
  });

  test(
    'ohne Plattformseite: unsupported statt MissingPluginException',
    () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        const ChannelMediaControlPort().send(MediaCommand.play),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.unsupported,
          ),
        ),
      );
    },
  );

  test('ungültiger Paketname wird abgewiesen', () {
    expect(
      () => const ChannelMediaControlPort().openApp('kein paket'),
      throwsArgumentError,
    );
  });
}
