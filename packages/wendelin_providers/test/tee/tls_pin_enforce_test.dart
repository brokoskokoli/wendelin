import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'provider_harness.dart';

/// SPKI hash the probe attestation lists for `api.redpill.ai`.
const _pinA =
    'c68585e7dc00a55d3082a9c860cb916e1788c5daec51505e413d27ab94f7d4c7';
const _pinB =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

Uint8List _cert(String name) => Uint8List.fromList(utf8.encode(name));

/// Gate whose „certificates“ are the names `A` and `B`.
TlsPinGate _gate() => TlsPinGate(
  spkiSha256: (der) {
    final pin = switch (utf8.decode(der)) {
      'A' => _pinA,
      'B' => _pinB,
      _ => throw const FormatException('Zertifikat nicht lesbar'),
    };
    return Uint8List.fromList([
      for (var i = 0; i < pin.length; i += 2)
        int.parse(pin.substring(i, i + 2), radix: 16),
    ]);
  },
);

/// Stand-in for [PinnedHttpClient]: decides like it does (before the request
/// goes to [_next]), with the certificate [cert] returns per connection.
final class _FakeConnectionClient extends http.BaseClient {
  _FakeConnectionClient(this._next, this.gate, this.enforce, this.cert);

  final http.Client _next;
  final TlsPinGate gate;
  final bool enforce;
  final Uint8List? Function() cert;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (enforce) {
      gate.enforce(cert());
    } else {
      gate.resetObserved();
      gate.observe(cert());
    }
    return _next.send(request);
  }
}

TeeHarness _harness(TlsPinGate gate, Uint8List? Function() cert) => TeeHarness(
  baseUrl: Uri.parse('https://api.redpill.ai/v1'),
  tlsPin: gate,
  pinWrap: (base, {required enforce}) =>
      _FakeConnectionClient(base, gate, enforce, cert),
);

void main() {
  group('TLS-Pin erzwingen (WP61)', () {
    test('passender Pin: Anfrage geht raus, Stufe TLS „geprüft“', () async {
      final gate = _gate();
      final h = _harness(gate, () => _cert('A'));
      final events = await h.chat();
      expect(events.last, isA<Done>());
      expect(h.chatRequests, 1);
      final tls = h.provider.lastSessionStages.firstWhere(
        (s) => s.stage == AttestationStage.tlsSpki,
      );
      expect(tls.outcome, StageOutcome.pass);
      expect(gate.expected, _pinA);
    });

    test('Zertifikat weicht in der Attestierung ab: keine Anfrage', () async {
      final h = _harness(_gate(), () => _cert('B'));
      final events = await h.chat();
      final error = (events.single as ErrorEvent).error;
      expect(error, isA<AttestationFailedException>());
      expect((error as AttestationFailedException).stage, 'tls.spki');
      expect(h.chatRequests, 0);
      expect(h.provider.locked, isTrue);
      // The mismatch was found in the attestation itself: exactly one
      // attestation, stage tls.spki is red.
      expect(h.server.count('aci/attestation'), 1);
      expect(
        h.provider.lastSessionStages
            .firstWhere((s) => s.stage == AttestationStage.tlsSpki)
            .outcome,
        StageOutcome.fail,
      );
    });

    test('Zertifikat nicht messbar: keine Anfrage (fail-closed)', () async {
      final h = _harness(_gate(), () => null);
      final events = await h.chat();
      expect(events.single, isA<ErrorEvent>());
      expect(h.chatRequests, 0);
    });

    test('Pin fehlt in der Attestierung: keine Anfrage', () async {
      final gate = _gate();
      final h = TeeHarness(
        baseUrl: Uri.parse('https://anderer-host.test/v1'),
        tlsPin: gate,
        pinWrap: (base, {required enforce}) =>
            _FakeConnectionClient(base, gate, enforce, () => _cert('A')),
      );
      final events = await h.chat();
      expect(events.single, isA<ErrorEvent>());
      expect(h.chatRequests, 0);
      expect(gate.expected, isNull);
    });

    test('Pin passt nicht zur Chat-Verbindung: einmal neu attestieren, dann Erfolg', () async {
      final gate = _gate();
      var chatConnections = 0;
      final h = TeeHarness(
        baseUrl: Uri.parse('https://api.redpill.ai/v1'),
        tlsPin: gate,
        pinWrap: (base, {required enforce}) => _FakeConnectionClient(
          base,
          gate,
          enforce,
          // First content connection still shows the old certificate.
          () => enforce && chatConnections++ == 0 ? _cert('B') : _cert('A'),
        ),
      );
      final events = await h.chat();
      expect(events.last, isA<Done>());
      expect(h.server.count('aci/attestation'), 2);
      expect(h.chatRequests, 1);
      expect(h.provider.locked, isFalse);
    });

    test('Pin passt auch nach der Re-Attestierung nicht: Fehler, gesperrt, nie gesendet', () async {
      final gate = _gate();
      final h = TeeHarness(
        baseUrl: Uri.parse('https://api.redpill.ai/v1'),
        tlsPin: gate,
        pinWrap: (base, {required enforce}) => _FakeConnectionClient(
          base,
          gate,
          enforce,
          () => enforce ? _cert('B') : _cert('A'),
        ),
      );
      final events = await h.chat();
      final error = (events.single as ErrorEvent).error;
      expect(error, isA<AttestationFailedException>());
      expect((error as AttestationFailedException).stage, 'tls.spki');
      expect(h.server.count('aci/attestation'), 2);
      expect(h.chatRequests, 0);
      expect(h.provider.locked, isTrue);
      // Locked: the next request neither attests nor sends.
      await h.chat();
      expect(h.server.count('aci/attestation'), 2);
      expect(h.chatRequests, 0);
    });

    test('listModels ohne Attestierung ist nicht möglich', () async {
      final h = _harness(_gate(), () => _cert('B'));
      await expectLater(
        h.provider.listModels(),
        throwsA(isA<AttestationFailedException>()),
      );
      expect(h.server.count('models'), 0);
    });
  });

  test('Fabrik: Phala-Profil bekommt einen erzwingenden und einen messenden Client', () {
    final built = <bool>[];
    final provider = ProviderFactory.create(
      ProviderProfile(
        id: 'phala',
        name: 'Phala',
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://api.redpill.ai/v1',
        defaultModel: 'm',
        privacy: PrivacyLevel.tee,
        authMethod: const ApiKeyAuth('ref'),
        options: const {'attestation': 'phala'},
      ),
      (_) async => 'k',
      attestation: AttestationWiring(
        crypto: FakeAttestationCrypto(),
        pinnedClient: (gate, {required enforce}) {
          built.add(enforce);
          return _FakeConnectionClient(
            http.Client(),
            gate,
            enforce,
            () => null,
          );
        },
      ),
    );
    expect(provider, isA<AttestedProvider>());
    expect(built.toSet(), {true, false});
    // adapter (enforcing), attestation (open), receipts (enforcing, with key)
    expect(built, [true, false, true]);
  });
}
