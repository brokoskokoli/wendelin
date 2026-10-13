import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_network_status.dart';
import 'package:wendelin/platform/document_text_import.dart';
import 'package:wendelin/platform/saf_list_file_port.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('ChannelNetworkStatus (Mock-Kanal statt NetworkChannel.kt)', () {
    const channel = MethodChannel(networkChannelName);
    late String answer;
    late List<String> calls;

    setUp(() {
      answer = 'online';
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method != 'state') throw MissingPluginException();
        if (answer == 'fehler') throw PlatformException(code: 'failed');
        return answer;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    /// Pushes `changed` from the platform side like the network callback.
    Future<void> push(Object? state) => messenger.handlePlatformMessage(
      networkChannelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('changed', state),
      ),
      (_) {},
    );

    test('fragt beim Start den Zustand ab', () async {
      answer = 'metered';
      final status = ChannelNetworkStatus();
      expect(status.current, NetworkState.online, reason: 'vor der Antwort');
      await status.start();
      addTearDown(status.dispose);
      expect(calls, ['state']);
      expect(status.current, NetworkState.metered);
    });

    test('übernimmt Änderungen der Plattform', () async {
      final status = ChannelNetworkStatus();
      await status.start();
      addTearDown(status.dispose);
      await push('offline');
      expect(status.current, NetworkState.offline);
      await push('online');
      expect(status.current, NetworkState.online);
      await push('unsinn');
      expect(
        status.current,
        NetworkState.online,
        reason: 'Unbekanntes zählt nicht',
      );
    });

    test('Fehler und fehlender Kanal behalten den letzten Zustand', () async {
      final status = ChannelNetworkStatus();
      await status.start();
      addTearDown(status.dispose);
      // Online bekannt: ein Fehler darf weder offline noch etwas anderes
      // erzwingen.
      expect(status.current, NetworkState.online);
      answer = 'fehler';
      await status.refresh();
      expect(status.current, NetworkState.online);
      await push('offline');
      await status.refresh();
      expect(status.current, NetworkState.offline);

      messenger.setMockMethodCallHandler(channel, null);
      final fresh = ChannelNetworkStatus();
      await fresh.refresh();
      expect(fresh.current, NetworkState.online);
    });

    test('parse kennt genau die drei Zustände', () {
      expect(ChannelNetworkStatus.parse('offline'), NetworkState.offline);
      expect(ChannelNetworkStatus.parse('online'), NetworkState.online);
      expect(ChannelNetworkStatus.parse('metered'), NetworkState.metered);
      expect(ChannelNetworkStatus.parse(null), isNull);
      expect(ChannelNetworkStatus.parse(1), isNull);
    });
  });

  group('DocumentTextImport', () {
    const channel = MethodChannel(filesChannelName);
    late List<MethodCall> calls;
    late Object? Function(MethodCall) reply;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('wählt JSON, liest UTF-8 und gibt die Freigabe zurück', () async {
      reply = (call) => switch (call.method) {
        'openDocument' => 'content://doc/1',
        'read' => Uint8List.fromList(utf8.encode('{"ä": 1}')),
        _ => null,
      };
      expect(await const DocumentTextImport().pick(), '{"ä": 1}');
      expect(calls.map((c) => c.method), ['openDocument', 'read', 'release']);
      expect(
        (calls.first.arguments as Map<Object?, Object?>)['mimeTypes'],
        DocumentTextImport.jsonTypes,
      );
    });

    test('abgebrochen: null, nichts gelesen', () async {
      reply = (_) => null;
      expect(await const DocumentTextImport().pick(), isNull);
      expect(calls.map((c) => c.method), ['openDocument']);
    });

    test('Fehler werden zu PortException', () async {
      reply = (call) => call.method == 'openDocument'
          ? throw PlatformException(code: 'unsupported')
          : null;
      await expectLater(
        const DocumentTextImport().pick(),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.unsupported,
          ),
        ),
      );
      reply = (call) => switch (call.method) {
        'openDocument' => 'content://doc/2',
        'read' => Uint8List.fromList([0xff, 0xfe]),
        _ => null,
      };
      await expectLater(
        const DocumentTextImport().pick(),
        throwsA(isA<PortException>()),
      );
      expect(calls.last.method, 'release', reason: 'auch nach Fehler');
    });
  });
}
