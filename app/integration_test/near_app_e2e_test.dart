// Gerätetest (WP75): NEAR-AI-Profil in der echten App auf dem Emulator. Der Provider kommt aus
// der echten Factory-Verdrahtung (`llmProviderFactoryProvider`, AttestedProvider, NearVerifier,
// NearE2eeChannel) mit dem Rust-Prüfmodul (`RustAttestationCrypto`): die beiden TDX-Quotes des
// aufgezeichneten Berichts werden echt gegen das aufgezeichnete Intel-Kollateral geprüft, die
// Verschlüsselung (X25519, XChaCha20-Poly1305) ist der echte Rust-Code. Ersetzt sind nur der
// Transport (aufgezeichneter Bericht, Dienst mit eigenem Schlüssel, Uhr und Nonce der
// Aufzeichnung), die Kollateralquelle und die Ed25519-Prüfung der Quittung (der Signaturschlüssel
// des Modells ist nicht verfügbar). Kein Netz.
//
// Läuft über `tool/e2e_android.sh` (nur Emulator).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/near_gateway.dart';
import 'support/tee_fixtures.g.dart';
import 'support/tee_gateway.dart'
    show FixturePinnedClient, fixtureGatewayCertificate, pcsFixtureClient;

/// Rust check module with the recorded collateral (the two NEAR platforms
/// differ), the receipt signature counted as valid, the recorded model key
/// swapped for the fixture service's key when encrypting, and the stand-in
/// certificate mapped to the pin of the recorded gateway quote.
final class _NearSubstitute implements AttestationCrypto, NearCrypto {
  _NearSubstitute(this._rust, this._service, this._quotes);

  final RustAttestationCrypto _rust;
  final FakeNearService _service;

  /// Collateral JSON per quote (hex of the quote → bytes).
  final Map<String, Uint8List> _quotes;

  @override
  Future<QuoteCollateral> collateralFor(Uint8List quote) async =>
      QuoteCollateral(_quotes[_hex(quote)] ?? Uint8List(0));

  @override
  Future<QuoteVerdict> verifyQuote(
    Uint8List quote,
    QuoteCollateral collateral,
    DateTime now,
  ) => _rust.verifyQuote(quote, collateral, now);

  @override
  bool verifyEd25519(Uint8List k, Uint8List m, Uint8List s) => true;

  @override
  Uint8List sha256(Uint8List d) => _rust.sha256(d);

  @override
  Uint8List sha384(Uint8List d) => _rust.sha384(d);

  @override
  Uint8List spkiSha256(Uint8List certificateDer) {
    if (listEquals(certificateDer, fixtureGatewayCertificate)) {
      return Uint8List.fromList([
        for (var i = 0; i < nearGatewayPin.length; i += 2)
          int.parse(nearGatewayPin.substring(i, i + 2), radix: 16),
      ]);
    }
    return _rust.spkiSha256(certificateDer);
  }

  @override
  E2eeKeypair e2eeGenerateKeypair() => _rust.e2eeGenerateKeypair();

  @override
  String e2eeEncrypt(Uint8List r, Uint8List p, Uint8List a) =>
      _rust.e2eeEncrypt(r, p, a);

  @override
  Uint8List e2eeDecrypt(Uint8List s, String w, Uint8List a) =>
      _rust.e2eeDecrypt(s, w, a);

  @override
  NearIdentity nearGenerateIdentity() => _rust.nearGenerateIdentity();

  @override
  String nearEncrypt(Uint8List recipient, Uint8List plaintext) =>
      _rust.nearEncrypt(
        _hex(recipient) == nearRecordedModelKeyHex
            ? _service.identity.public
            : recipient,
        plaintext,
      );

  @override
  Uint8List nearDecrypt(Uint8List secret, String wireHex) =>
      _rust.nearDecrypt(secret, wireHex);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(E2eApp, NearFixtureGateway, ProviderContainer)> start(
    WidgetTester tester,
  ) async {
    final gateway = NearFixtureGateway();
    final backend = await FrbAttestBackend.init();
    final tmp = Directory.systemTemp.createTempSync('near-app-e2e');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final report = nearReportQuotes();
    final app = E2eApp(
      extraOverrides: [
        attestationTransportProvider.overrideWithValue(
          AttestationTransport(
            client: gateway.client,
            pinnedClient: (gate, {required enforce}) =>
                FixturePinnedClient(gateway.client, gate, enforce: enforce),
            settings: HttpSettings(clock: FixedClock(nearNow)),
            nonceSource: () => nearNonce,
          ),
        ),
        attestationCryptoProvider.overrideWith(
          (ref) async => _NearSubstitute(
            RustAttestationCrypto(
              backend: backend,
              pcs: PcsCollateralClient(
                client: pcsFixtureClient(),
                backend: backend,
              ),
              cache: CollateralCache(dir: tmp, now: () => nearNow),
              clock: () => nearNow,
            ),
            gateway.service,
            report,
          ),
        ),
      ],
    );
    await app.storage.providerProfiles.save(
      ProviderProfile(
        id: 'near',
        name: 'NEAR AI (TEE)',
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://cloud-api.near.ai/v1',
        defaultModel: nearModelId,
        privacy: PrivacyLevel.tee,
        authMethod: const ApiKeyAuth('provider.near.apiKey'),
        options: const {
          'attestation': 'near',
          'ownedBy': 'nearai',
          'toolsOnly': true,
        },
      ),
    );
    await app.storage.providerProfiles.setDefault('near');
    await app.secrets.write('provider.near.apiKey', 'e2e-key');
    final c = await app.pump(tester);
    return (app, gateway, c);
  }

  testWidgets('Text-Anfrage an das NEAR-Profil: grünes Schild, Protokoll mit '
      'allen Stufen, Tools nicht im Klartext', (tester) async {
    final (app, gateway, _) = await start(tester);
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.textContaining('Ruhig: 0,4 m Welle.'));
    await pumpUntil(tester, find.textContaining(l10n(tester).attSummaryGreen));
    expect(gateway.chats, 1);
    expect(find.byType(StatusCard), findsNothing);

    final records = await app.storage.attestations.latest();
    final receipt = records.firstWhere(
      (r) => r.kind == AttestationRecordKind.receipt,
    );
    expect(receipt.status, AttestationStatus.green);
    expect(receipt.receiptId, 'near-chat-1');
    expect(
      receipt.stages.map((s) => s.stage),
      containsAll(['receipt.signature', 'receipt.request', 'receipt.response']),
    );
    final session = records.firstWhere(
      (r) => r.kind == AttestationRecordKind.session,
    );
    expect(
      session.stages.map((s) => s.stage),
      containsAll(['quote', 'tcb', 'nonce', 'eventlog', 'compose', 'gateway']),
    );
    expect(session.stages.every((s) => s.result != 'fail'), isTrue);
    // E2EE with tools: the service decrypted real Rust cipher text, and
    // neither the question nor any tool name was on the wire in plaintext.
    final plain = gateway.lastPlainBody!;
    final messages = plain['messages']! as List<Object?>;
    expect(
      messages.map((m) => (m! as Map)['content']),
      contains('Wie wird das Meer morgen?'),
    );
    expect(gateway.lastWire, isNot(contains('Wie wird das Meer morgen?')));
    final tools = plain['tools'] as List<Object?>?;
    expect(tools, isNotEmpty, reason: 'die App sendet ihren Werkzeugkatalog');
    final firstTool =
        ((tools!.first! as Map)['function']! as Map)['name']! as String;
    expect(gateway.lastWire, isNot(contains(firstTool)));
  });

  testWidgets('Dienst antwortet unverschlüsselt: Antwort wird nie angezeigt', (
    tester,
  ) async {
    final (_, gateway, _) = await start(tester);
    gateway.plainAnswer = true;
    await send(tester, 'Wie wird das Meer morgen?');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(gateway.chats, 1);
    expect(find.textContaining('Ruhig: 0,4 m Welle.'), findsNothing);
  });

  testWidgets('Manipulierte Quittung: rotes Schild, Anbieter gesperrt, '
      'nichts Weiteres gesendet', (tester) async {
    final (app, gateway, c) = await start(tester);
    gateway.tamper = (doc) {
      final parts = (doc['text']! as String).split(':');
      parts[parts.length - 1] = '0' * 64;
      doc['text'] = parts.join(':');
    };
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.text('Neu prüfen'));
    expect(find.text('Prüfung fehlgeschlagen'), findsWidgets);
    expect(c.read(attestationHubProvider).isLocked('near'), isTrue);

    await send(tester, 'Noch eine Frage');
    await waitIdle(tester);
    expect(gateway.chats, 1, reason: 'gesperrt: nichts mehr gesendet');
    final red = (await app.storage.attestations.latest()).where(
      (r) => r.status == AttestationStatus.red,
    );
    expect(red, isNotEmpty);
  });
}

/// Collateral per quote of the recorded NEAR report.
Map<String, Uint8List> nearReportQuotes() {
  final report = jsonDecode(nearReport) as Map<String, Object?>;
  final model =
      (report['model_attestations']! as List<Object?>).first!
          as Map<String, Object?>;
  final gateway = report['gateway_attestation']! as Map<String, Object?>;
  return {
    _hex(_unhex(model['intel_quote']! as String)): _bytes(nearCollateralModel),
    _hex(_unhex(gateway['intel_quote']! as String)): _bytes(
      nearCollateralGateway,
    ),
  };
}
