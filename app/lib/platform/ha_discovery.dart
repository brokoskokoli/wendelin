import 'dart:async';

import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

/// Service type Home Assistant announces itself with.
const haServiceType = '_home-assistant._tcp.local';

/// The server announced by one mDNS service: the TXT address
/// (`internal_url`, then `base_url`) if it is allowed (`HaUrl.parse`),
/// else the IPv4 address or the host name from SRV with [port]. `null` if
/// no allowed address results. [txt] holds `key=value` lines.
HaServer? haServerFrom({
  required String instance,
  required String target,
  required int port,
  List<String> txt = const [],
  String? ipv4,
}) {
  final values = <String, String>{};
  for (final line in txt) {
    final eq = line.indexOf('=');
    if (eq > 0) values[line.substring(0, eq)] = line.substring(eq + 1);
  }
  final host = target.endsWith('.')
      ? target.substring(0, target.length - 1)
      : target;
  final candidates = [
    values['internal_url'],
    values['base_url'],
    if (ipv4 != null) 'http://$ipv4:$port',
    if (host.isNotEmpty) 'http://$host:$port',
  ];
  for (final c in candidates) {
    if (c == null || c.isEmpty) continue;
    try {
      final name = values['location_name'] ?? instance.split('._').first;
      return HaServer(name: name, url: HaUrl.parse(c));
    } on PortException {
      continue;
    }
  }
  return null;
}

/// [HaDiscovery] over mDNS (`_home-assistant._tcp`) in the Wi-Fi, with a
/// multicast lock from Kotlin (`MulticastChannel`). Does not work over
/// Tailscale: enter the address by hand there.
final class MdnsHaDiscovery implements HaDiscovery {
  /// Creates the discovery; [client] and [channel] are injectable for tests.
  MdnsHaDiscovery({MDnsClient Function()? client, MethodChannel? channel})
    : _client = client ?? MDnsClient.new,
      _channel = channel ?? const MethodChannel(multicastChannelName);

  final MDnsClient Function() _client;
  final MethodChannel _channel;

  @override
  Future<List<HaServer>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final found = <String, HaServer>{};
    final client = _client();
    try {
      try {
        await _channel.invokeMethod<void>('acquire');
      } on Object {
        // Without the lock the search may find less; it still runs.
      }
      await client.start();
      final pointers = client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(haServiceType),
        timeout: timeout,
      );
      await for (final ptr in pointers) {
        final server = await _resolve(client, ptr.domainName, timeout);
        if (server != null) found[server.url] = server;
      }
    } on Object {
      // Never throws: the setup falls back to typing the address.
    } finally {
      client.stop();
      try {
        await _channel.invokeMethod<void>('release');
      } on Object {
        // Nothing to release.
      }
    }
    return found.values.toList();
  }

  Future<HaServer?> _resolve(
    MDnsClient client,
    String name,
    Duration timeout,
  ) async {
    final srv = await _first(
      client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(name),
        timeout: timeout,
      ),
    );
    if (srv == null) return null;
    final txt = <String>[];
    await for (final t in client.lookup<TxtResourceRecord>(
      ResourceRecordQuery.text(name),
      timeout: const Duration(seconds: 1),
    )) {
      txt.addAll(t.text.split('\n'));
    }
    final ip = await _first(
      client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
        timeout: const Duration(seconds: 1),
      ),
    );
    return haServerFrom(
      instance: name,
      target: srv.target,
      port: srv.port,
      txt: txt,
      ipv4: ip?.address.address,
    );
  }
}

Future<T?> _first<T>(Stream<T> stream) async {
  await for (final item in stream) {
    return item;
  }
  return null;
}
