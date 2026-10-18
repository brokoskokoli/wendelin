import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:wendelin/platform/channels.dart';
import 'package:wendelin/platform/ha_discovery.dart';

final class _BrokenClient extends MDnsClient {
  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) => throw const SocketException('kein WLAN');
}

void main() {
  group('haServerFrom', () {
    test('TXT internal_url gewinnt, Name aus location_name', () {
      final s = haServerFrom(
        instance: 'Zuhause._home-assistant._tcp.local',
        target: 'ha.local.',
        port: 8123,
        txt: ['location_name=Daheim', 'internal_url=http://192.168.1.20:8123/'],
        ipv4: '192.168.1.99',
      );
      expect(s!.name, 'Daheim');
      expect(s.url, 'http://192.168.1.20:8123');
    });

    test('ohne TXT: IPv4 aus A-Record, sonst Host aus SRV', () {
      expect(
        haServerFrom(
          instance: 'Zuhause._home-assistant._tcp.local',
          target: 'ha.local.',
          port: 8123,
          ipv4: '192.168.1.99',
        )!.url,
        'http://192.168.1.99:8123',
      );
      expect(
        haServerFrom(
          instance: 'Zuhause._home-assistant._tcp.local',
          target: 'ha.local.',
          port: 8123,
        )!.url,
        'http://ha.local:8123',
      );
    });

    test('unzulässige Adressen werden übersprungen (kein http zu öffentlichen Hosts)', () {
      final s = haServerFrom(
        instance: 'X._home-assistant._tcp.local',
        target: 'evil.example.com.',
        port: 8123,
        txt: ['base_url=http://evil.example.com:8123'],
        ipv4: '192.168.1.5',
      );
      expect(s!.url, 'http://192.168.1.5:8123');
      expect(
        haServerFrom(
          instance: 'X._home-assistant._tcp.local',
          target: 'evil.example.com.',
          port: 8123,
          txt: ['base_url=http://evil.example.com'],
        ),
        isNull,
      );
    });
  });

  test(
    'Fehler beim Start: leere Liste, Multicast-Lock wird freigegeben',
    () async {
      final calls = <String>[];
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(multicastChannelName), (
            call,
          ) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(multicastChannelName),
              null,
            ),
      );
      final d = MdnsHaDiscovery(client: _BrokenClient.new);
      expect(
        await d.discover(timeout: const Duration(milliseconds: 100)),
        isEmpty,
      );
      expect(calls, ['acquire', 'release']);
    },
  );
}
