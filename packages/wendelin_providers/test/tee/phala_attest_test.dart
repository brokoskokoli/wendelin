import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'fixture_suite.dart';
import 'tee_support.dart';

void main() {
  gatewayFixtureTests(FakeAttestationCrypto.new, name: 'FakeAttestationCrypto');

  group('PhalaVerifier.attest (Fake-Krypto)', () {
    test(
      'Quote ungültig → Quote rot, Nonce und Event-Log nicht prüfbar',
      () async {
        final crypto = FakeAttestationCrypto(
          quoteError: const QuoteVerificationException('Signatur ungültig'),
        );
        final r = await probeVerifier(attestationServer(), crypto).attest();
        expect(r.status, AttestationStatus.red);
        expect(stagesWith(r.stages, StageOutcome.fail), [
          AttestationStage.quote,
        ]);
        expect(
          r.stages.map((s) => s.stage),
          isNot(contains(AttestationStage.nonceBinding)),
        );
        expect(r.session, isNull);
      },
    );

    test(
      'Kollateral nicht erreichbar → gelb (unavailable), keine Sitzung',
      () async {
        final crypto = FakeAttestationCrypto(
          collateralError: const CollateralUnavailableException('offline'),
        );
        final r = await probeVerifier(attestationServer(), crypto).attest();
        expect(r.status, AttestationStatus.yellow);
        expect(stagesWith(r.stages, StageOutcome.unavailable), [
          AttestationStage.quote,
        ]);
        expect(r.session, isNull);
      },
    );

    test('Attestierungs-Endpunkt 503 → gelb', () async {
      final server = TeeServer({'aci/attestation': jsonBody({}, status: 503)});
      final r = await probeVerifier(server, FakeAttestationCrypto()).attest();
      expect(r.status, AttestationStatus.yellow);
    });

    test(
      'Pflichtfeld fehlt → Fehler mit Prüfstufe, unbekannte Felder egal',
      () async {
        final doc = copyJson(teeJson('gateway_attestation'))
          ..['neu'] = {'x': 1};
        final ok = await probeVerifier(
          attestationServer(doc),
          FakeAttestationCrypto(),
        ).attest();
        expect(ok.status, AttestationStatus.green);

        final att = doc['attestation']! as Map<String, Object?>;
        att.remove('report_data');
        final r = await probeVerifier(
          attestationServer(doc),
          FakeAttestationCrypto(),
        ).attest();
        expect(r.status, AttestationStatus.red);
        expect(r.firstProblem?.stage, AttestationStage.nonceBinding);
        expect(r.firstProblem?.detail, contains('report_data'));
      },
    );

    test(
      'TCB-Hinweise bleiben grün mit Notiz, OutOfDate und Revoked sind rot',
      () async {
        for (final (status, expected) in [
          (TcbStatus.upToDate, AttestationStatus.green),
          (TcbStatus.swHardeningNeeded, AttestationStatus.green),
          (TcbStatus.configurationNeeded, AttestationStatus.green),
          (
            TcbStatus.configurationAndSwHardeningNeeded,
            AttestationStatus.green,
          ),
          (TcbStatus.outOfDate, AttestationStatus.red),
          (TcbStatus.outOfDateConfigurationNeeded, AttestationStatus.red),
          (TcbStatus.revoked, AttestationStatus.red),
        ]) {
          final r = await probeVerifier(
            attestationServer(),
            FakeAttestationCrypto(
              tcbStatus: status,
              advisoryIds: const ['INTEL-SA-00837'],
            ),
          ).attest();
          expect(r.status, expected, reason: status.name);
          if (status != TcbStatus.upToDate) {
            final tcb = r.stages.firstWhere(
              (s) => s.stage == AttestationStage.tcb,
            );
            expect(tcb.detail, contains('INTEL-SA-00837'));
          }
          if (expected == AttestationStatus.green &&
              status != TcbStatus.upToDate) {
            expect(r.notes.single, contains(status.name));
          }
        }
      },
    );

    test(
      'Provenance: leere Liste nur protokolliert, sonst gegen Liste',
      () async {
        Future<AttestationResult> run(Set<String> trusted) => probeVerifier(
          attestationServer(),
          FakeAttestationCrypto(),
          trustedCommits: trusted,
        ).attest();
        const commit = '24a31ff1b33cb45cd2ad0ddac02749eb4ea424e2';
        final none = await run({});
        expect(none.status, AttestationStatus.green);
        expect(
          none.stages
              .firstWhere((s) => s.stage == AttestationStage.provenance)
              .outcome,
          StageOutcome.info,
        );
        expect((await run({commit})).status, AttestationStatus.green);
        final other = await run({'deadbeef'});
        expect(other.status, AttestationStatus.red);
        expect(stagesWith(other.stages, StageOutcome.fail), [
          AttestationStage.provenance,
        ]);
      },
    );

    test('TLS-SPKI: Keyset/Binding konsistent; Abweichung der Verbindung nur auf Wunsch rot', () async {
      PhalaVerifier verifier(String? seen, {bool enforce = false}) =>
          PhalaVerifier(
            crypto: FakeAttestationCrypto(),
            baseUrl: Uri.parse('https://gateway.test/v1'),
            profileId: 'p',
            client: attestationServer().client,
            settings: HttpSettings(clock: FixedClock(probeNow)),
            nonceSource: () => probeNonce,
            observedSpki: () async => seen,
            enforceTlsPin: enforce,
          );
      const listed =
          'c68585e7dc00a55d3082a9c860cb916e1788c5daec51505e413d27ab94f7d4c7';
      Future<StageResult> tls(PhalaVerifier v) async => (await v.attest())
          .stages
          .firstWhere((s) => s.stage == AttestationStage.tlsSpki);
      expect((await tls(verifier(listed))).outcome, StageOutcome.pass);
      // The observed certificates of the probe do not match the keyset
      // (ADR 0014): logged, not red, unless enforced.
      expect((await tls(verifier('6ebb83be'))).outcome, StageOutcome.info);
      expect(
        (await tls(verifier('6ebb83be', enforce: true))).outcome,
        StageOutcome.fail,
      );

      final doc = copyJson(teeJson('gateway_attestation'));
      (((doc['attestation']! as Map)['evidence']!
                  as Map)['downstream_tls_binding']!
              as Map)['spki_sha256'] =
          'ff' * 32;
      final r = await probeVerifier(
        attestationServer(doc),
        FakeAttestationCrypto(),
      ).attest();
      expect(stagesWith(r.stages, StageOutcome.fail), [
        AttestationStage.tlsSpki,
      ]);
    });

    test('Pinning: erste Attestierung pinnt, gleiche ändert nichts, Wechsel meldet changed', () async {
      final pins = InMemoryAttestationPinStore();
      Future<PinChange> run(Map<String, Object?>? doc) async =>
          (await probeVerifier(
            attestationServer(doc),
            FakeAttestationCrypto(),
            pins: pins,
          ).attest()).pinChange;
      expect(await run(null), PinChange.first);
      expect(await run(null), PinChange.none);
      // New compose + commit (the quote checks are the fake's business).
      final doc = copyJson(teeJson('gateway_attestation'));
      (((doc['attestation']! as Map)['source_provenance']!)
              as Map)['repo_commit'] =
          'abc';
      expect(await run(doc), PinChange.changed);
      expect((await pins.load('phala'))?.repoCommit, 'abc');
    });

    test(
      'Nonce ist pro Attestierung frisch und 32 Byte lang (Standardquelle)',
      () async {
        final server = attestationServer();
        final v = PhalaVerifier(
          crypto: FakeAttestationCrypto(),
          baseUrl: Uri.parse('https://gateway.test/v1'),
          profileId: 'p',
          client: server.client,
        );
        await v.attest();
        await v.attest();
        final nonces = [
          for (final r in server.requests) r.url.queryParameters['nonce']!,
        ];
        expect(nonces.toSet(), hasLength(2));
        expect(nonces.every((n) => n.length == 64), isTrue);
        expect(utf8.encode(nonces.first).length, 64);
        expect(Uint8List(0), isEmpty);
      },
    );
  });
}
