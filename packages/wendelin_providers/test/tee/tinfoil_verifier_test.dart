import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tinfoil_support.dart';

SnpVerdict _verdict({
  bool reportOk = true,
  bool chainOk = true,
  bool vcekMatchesReport = true,
  bool signatureOk = true,
  bool policyOk = true,
  bool tlsBound = true,
  bool hpkeBound = true,
  List<String> errors = const [],
}) => SnpVerdict(
  reportOk: reportOk,
  chainOk: chainOk,
  vcekMatchesReport: vcekMatchesReport,
  signatureOk: signatureOk,
  policyOk: policyOk,
  tlsBound: tlsBound,
  hpkeBound: hpkeBound,
  product: 'Genoa',
  errors: errors,
);

/// Key of the release floor: provider host and router repo.
const floorKey = 'inference.test/${TinfoilPolicy.repo}';

void main() {
  group('Richtlinie', () {
    test('min_tcb ist bewusst gesetzt: Bootloader 9, SNP 22, Microcode 80', () {
      const t = TinfoilPolicy.minTcb;
      expect((t.bootloader, t.tee, t.snp, t.microcode), (9, 0, 22, 80));
      expect(TinfoilPolicy.snpPolicy.minTcb, t);
    });

    test('die Richtlinie geht unverändert an die SNP-Prüfung', () async {
      final f = TinfoilFixture();
      await f.verifier().attest();
      final p = f.snp.lastPolicy!.minTcb;
      expect((p.bootloader, p.tee, p.snp, p.microcode), (9, 0, 22, 80));
    });
  });

  group('TinfoilVerifier grün', () {
    test(
      'alle Stufen, Sitzung aus report_data, kein Schlüssel an Dritte',
      () async {
        final f = TinfoilFixture();
        final pins = InMemoryAttestationPinStore();
        final result = await f.verifier(pins: pins).attest();
        expect(
          result.status,
          AttestationStatus.green,
          reason: '${result.stages}',
        );
        for (final s in [
          AttestationStage.snpReport,
          AttestationStage.snpChain,
          AttestationStage.snpPolicy,
          AttestationStage.bindHpke,
          AttestationStage.sigstoreRelease,
          AttestationStage.measurement,
          AttestationStage.releaseFloor,
          AttestationStage.e2eeKey,
        ]) {
          expect(stageOf(result, s).outcome, StageOutcome.pass, reason: s.id);
        }
        // „Keine Quittung je Antwort“ steht klar benannt als Information da.
        final none = stageOf(result, AttestationStage.noReceipt);
        expect(none.outcome, StageOutcome.info);
        expect(none.detail, contains('Keine Quittung je Antwort'));

        final session = result.session!;
        expect(session.reportData, f.service.reportData);
        expect(session.ehbpKeyConfig, f.service.keyConfig);
        expect(session.e2eeKey!.publicKey, f.service.publicKey);
        expect(session.repoCommit, 'v0.0.158');
        expect(session.composeHash, TinfoilFixture.measurement);
        expect(session.notAfter, tinfoilNow.add(const Duration(minutes: 30)));
        expect(result.pinChange, PinChange.first);
        // Der Messwert des Reports geht an den Release-Vergleich.
        expect(f.sigstore.last!.measurementHex, TinfoilFixture.measurement);
        expect(f.sigstore.last!.repo, TinfoilPolicy.repo);
        expect(f.sigstore.last!.tag, 'v0.0.158');
        expect(f.sigstore.last!.digestHex, 'ab' * 32);
        // Der Prozessor wird beim AMD-Schlüsseldienst mit dem TCB des Reports
        // gesucht.
        final vcek = f.requests.firstWhere(
          (r) => r.url.path.contains('/Genoa/a'),
        );
        expect(vcek.url.host, 'kdsintf.amd.com');
        expect(vcek.url.query, 'blSPL=10&teeSPL=0&snpSPL=23&ucodeSPL=84');
        // Nur öffentliche Quellen, nie mit Zugangsdaten.
        expect(
          f.requests.where((r) => r.headers.containsKey('authorization')),
          isEmpty,
        );
      },
    );

    test(
      'TLS-Pin aus report_data wird erst nach grüner Prüfung gesetzt',
      () async {
        final f = TinfoilFixture();
        final pin = f.service.tlsSpkiSha256;
        final gate = TlsPinGate(spkiSha256: (_) => pin);
        final result = await f
            .verifier(
              gate: gate,
              router: observingClient(f.client, gate, Uint8List(1)),
            )
            .attest();
        expect(
          result.status,
          AttestationStatus.green,
          reason: '${result.stages}',
        );
        expect(
          stageOf(result, AttestationStage.tlsSpki).outcome,
          StageOutcome.pass,
        );
        expect(gate.expected, AttestCodec.hex(pin));
        // Die SNP-Prüfung bekam den gemessenen Pin der Verbindung.
      },
    );

    test(
      'Sitzung wechselt der Pin bei neuem Messwert (Update des Routers)',
      () async {
        final f = TinfoilFixture();
        final pins = InMemoryAttestationPinStore();
        await f.verifier(pins: pins).attest();
        f.tag = 'v0.0.159';
        f.integratedTime += 10;
        f.sigstoreGreen();
        final second = await f.verifier(pins: pins).attest();
        expect(second.pinChange, PinChange.changed);
      },
    );
  });

  group('TinfoilVerifier: jede Bindung ist nötig', () {
    Future<AttestationResult> run(
      TinfoilFixture f, {
      TlsPinGate? gate,
      http.Client? router,
    }) => f.verifier(gate: gate, router: router).attest();

    test(
      'Signatur, Kette, Richtlinie: je eine rote Stufe, keine Sitzung',
      () async {
        final cases = <(String, SnpVerdict, AttestationStage)>[
          (
            'Signatur',
            _verdict(signatureOk: false),
            AttestationStage.snpReport,
          ),
          (
            'VCEK',
            _verdict(vcekMatchesReport: false),
            AttestationStage.snpReport,
          ),
          ('Kette', _verdict(chainOk: false), AttestationStage.snpChain),
          ('Richtlinie', _verdict(policyOk: false), AttestationStage.snpPolicy),
          (
            'Fehlertext',
            _verdict(errors: const ['Debug-Gast']),
            AttestationStage.snpReport,
          ),
        ];
        for (final (name, verdict, stage) in cases) {
          final f = TinfoilFixture();
          f.snp.verdict = verdict;
          final r = await run(f);
          expect(r.status, AttestationStatus.red, reason: name);
          expect(stageOf(r, stage).outcome, StageOutcome.fail, reason: name);
          expect(r.session, isNull, reason: name);
          expect(await f.floors.load(floorKey), isNull, reason: name);
        }
      },
    );

    test('HPKE-Schlüssel des Routers weicht von report_data ab: rot', () async {
      final f = TinfoilFixture();
      f.keyConfig = FakeEhbpService(
        secret: Uint8List.fromList(List.filled(32, 9)),
      ).keyConfig;
      final r = await run(f);
      expect(r.status, AttestationStatus.red);
      expect(stageOf(r, AttestationStage.bindHpke).outcome, StageOutcome.fail);
      expect(r.session, isNull);
    });

    test('SNP meldet den HPKE-Schlüssel nicht gebunden: rot', () async {
      final f = TinfoilFixture();
      f.snp.verdict = _verdict(hpkeBound: false);
      final r = await run(f);
      expect(r.status, AttestationStatus.red);
      expect(stageOf(r, AttestationStage.bindHpke).outcome, StageOutcome.fail);
    });

    test('Zertifikat der Verbindung weicht vom Report ab: rot', () async {
      final f = TinfoilFixture();
      final gate = TlsPinGate(spkiSha256: (_) => Uint8List(32));
      f.snp.verdict = _verdict(tlsBound: false);
      final r = await run(
        f,
        gate: gate,
        router: observingClient(f.client, gate, Uint8List(1)),
      );
      expect(r.status, AttestationStatus.red);
      expect(stageOf(r, AttestationStage.tlsSpki).outcome, StageOutcome.fail);
      expect(gate.expected, isNull);
    });

    test('Zertifikat der Verbindung nicht messbar: rot', () async {
      final f = TinfoilFixture();
      final gate = TlsPinGate(spkiSha256: (_) => Uint8List(32));
      final r = await run(f, gate: gate); // niemand misst
      expect(r.status, AttestationStatus.red);
      expect(
        stageOf(r, AttestationStage.tlsSpki).detail,
        contains('nicht messbar'),
      );
    });

    test(
      'der erwartete TLS-Pin kommt von der Verbindung, nicht vom Router',
      () async {
        final f = TinfoilFixture();
        final seen = Uint8List.fromList(List.generate(32, (i) => i));
        final gate = TlsPinGate(spkiSha256: (_) => seen);
        f.snp.verdict = _verdict(tlsBound: false); // weicht von report_data ab
        await run(
          f,
          gate: gate,
          router: observingClient(f.client, gate, Uint8List(1)),
        );
        // Die Fake-SNP-Prüfung hat den gemessenen Hash als Erwartung erhalten.
        expect(f.snp.lastTls, seen);
      },
    );

    test(
      'Sigstore: Signatur ungültig oder Messwert gehört nicht zum Release',
      () async {
        final bad = TinfoilFixture();
        bad.sigstore.verdict = SigstoreVerdict(
          dsseOk: true,
          chainOk: false,
          identityOk: true,
          rekorOk: true,
          measurementOk: true,
          integratedTime: bad.integratedTime,
        );
        var r = await run(bad);
        expect(r.status, AttestationStatus.red);
        expect(
          stageOf(r, AttestationStage.sigstoreRelease).outcome,
          StageOutcome.fail,
        );

        final other = TinfoilFixture();
        other.sigstore.verdict = SigstoreVerdict(
          dsseOk: true,
          chainOk: true,
          identityOk: true,
          rekorOk: true,
          measurementOk: false,
          integratedTime: other.integratedTime,
        );
        r = await run(other);
        expect(r.status, AttestationStatus.red);
        expect(
          stageOf(r, AttestationStage.measurement).outcome,
          StageOutcome.fail,
        );
        expect(
          stageOf(r, AttestationStage.measurement).detail,
          contains('neuesten'),
        );
        expect(r.session, isNull);
      },
    );

    test(
      'Format des Dokuments unbekannt, Report kaputt, gzip-Bombe: rot',
      () async {
        var f = TinfoilFixture()..format = 'sev-snp-guest/v9';
        expect((await run(f)).status, AttestationStatus.red);
        f = TinfoilFixture()..bodyOverride = '###';
        expect((await run(f)).status, AttestationStatus.red);
        f = TinfoilFixture()
          ..report = Uint8List(
            2 * 1024 * 1024,
          ); // dekomprimiert weit über 4 KiB
        final r = await run(f);
        expect(r.status, AttestationStatus.red);
        expect(f.snp.verifies, 0);
      },
    );
  });

  group('TinfoilVerifier: Quellen', () {
    test(
      'AMD-Schlüsseldienst: Produkt durch Probieren (Milan nach Genoa)',
      () async {
        final f = TinfoilFixture()..kdsProducts = {'Milan'};
        final r = await f.verifier().attest();
        expect(r.status, AttestationStatus.green, reason: '${r.stages}');
        final tried = [
          for (final q in f.requests)
            if (q.url.host == 'kdsintf.amd.com' &&
                !q.url.path.endsWith('cert_chain'))
              q.url.pathSegments[2],
        ];
        expect(tried, ['Genoa', 'Milan']);
      },
    );

    test('Prozessor bei keinem Produkt bekannt: rot, nicht nur gelb', () async {
      final f = TinfoilFixture()..kdsProducts = {};
      final r = await f.verifier().attest();
      expect(r.status, AttestationStatus.red);
      expect(f.snp.verifies, 0);
    });

    test('Quellen nicht erreichbar: gelb, nie grün, nichts gesetzt', () async {
      for (final route in [
        'kdsintf.amd.com/vcek/v1/Genoa/a',
        'releases/latest',
        '/.well-known/tinfoil-attestation',
        'attestations/sha256',
      ]) {
        final f = TinfoilFixture();
        f.failing[route] = 503;
        final r = await f.verifier().attest();
        expect(r.status, AttestationStatus.yellow, reason: route);
        expect(r.session, isNull, reason: route);
        expect(await f.floors.load(floorKey), isNull, reason: route);
      }
    });

    test('tag_name nicht lesbar: rot', () async {
      final f = TinfoilFixture()..tag = 'nightly';
      final r = await f.verifier().attest();
      expect(r.status, AttestationStatus.red);
    });

    test(
      'die Anfrage an den Router und die Quellen tragen keinen API-Key',
      () async {
        final f = TinfoilFixture();
        await f.verifier().attest();
        for (final q in f.requests) {
          expect(
            q.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
        }
        final hosts = f.requests.map((q) => q.url.host).toSet();
        expect(hosts, {
          'inference.test',
          'kdsintf.amd.com',
          'api.github.com',
          'github.com',
        });
      },
    );

    test(
      'Stufentexte enthalten keine Schlüssel und kein report_data',
      () async {
        final f = TinfoilFixture();
        f.snp.verdict = _verdict(chainOk: false);
        final r = await f.verifier().attest();
        final text = jsonEncode([for (final s in r.stages) s.toJson()]);
        expect(text, isNot(contains(AttestCodec.hex(f.service.publicKey))));
        expect(text, isNot(contains(AttestCodec.hex(f.service.reportData))));
      },
    );
  });

  group('Rückschrittschutz (K59)', () {
    test(
      'höchste gesehene Release-Version wird gespeichert und nur erhöht',
      () async {
        final f = TinfoilFixture(tag: 'v0.0.158');
        await f.verifier().attest();
        expect((await f.floors.load(floorKey))!.version.toString(), 'v0.0.158');
        f.tag = 'v0.0.159';
        f.integratedTime += 100;
        f.sigstoreGreen();
        await f.verifier().attest();
        final floor = (await f.floors.load(floorKey))!;
        expect(floor.version.toString(), 'v0.0.159');
        expect(floor.integratedTime, f.integratedTime);
      },
    );

    test(
      'Replay alter Release-Daten (v0.0.158 nach v0.0.159) ist rot',
      () async {
        final f = TinfoilFixture(tag: 'v0.0.159', integratedTime: 1789000500);
        expect((await f.verifier().attest()).status, AttestationStatus.green);
        // Ein Angreifer spielt das (gültig signierte) alte Release und den
        // passenden alten Router-Zustand ein.
        f
          ..tag = 'v0.0.158'
          ..integratedTime = 1789000000
          ..sigstoreGreen();
        final r = await f.verifier().attest();
        expect(r.status, AttestationStatus.red);
        expect(
          stageOf(r, AttestationStage.releaseFloor).outcome,
          StageOutcome.fail,
        );
        expect(
          stageOf(r, AttestationStage.releaseFloor).detail,
          contains('Rückschritt'),
        );
        expect(r.session, isNull);
        expect((await f.floors.load(floorKey))!.version.toString(), 'v0.0.159');
      },
    );

    test('gleiche Version mit früherer Signierzeit ist rot', () async {
      final f = TinfoilFixture(tag: 'v0.0.158', integratedTime: 1789000500);
      await f.verifier().attest();
      f
        ..integratedTime = 1789000499
        ..sigstoreGreen();
      final r = await f.verifier().attest();
      expect(r.status, AttestationStatus.red);
      expect(
        stageOf(r, AttestationStage.releaseFloor).outcome,
        StageOutcome.fail,
      );
    });

    test(
      'Untergrenze gilt je Anbieter-Host: ein neues Profil erbt sie (K59)',
      () async {
        final f = TinfoilFixture(tag: 'v0.0.159');
        await f.verifier().attest();
        f
          ..tag = 'v0.0.158'
          ..sigstoreGreen();
        final fresh = await f.verifier(profileId: 'zweites').attest();
        expect(fresh.status, AttestationStatus.red);
        expect(
          stageOf(fresh, AttestationStage.releaseFloor).detail,
          contains('Rückschritt'),
        );
        // Ein anderer Anbieter-Host hat seine eigene Untergrenze.
        final other = await f.verifier(host: 'anders.test').attest();
        expect(other.status, AttestationStatus.green);
      },
    );

    test('eine ältere Untergrenze unter der Profil-Id zählt weiter', () async {
      final f = TinfoilFixture(tag: 'v0.0.158');
      await f.floors.save(
        'altprofil',
        ReleaseFloor(
          version: ReleaseVersion.tryParse('v0.0.170')!,
          integratedTime: 1,
        ),
      );
      final r = await f.verifier(profileId: 'altprofil').attest();
      expect(r.status, AttestationStatus.red);
      expect(
        stageOf(r, AttestationStage.releaseFloor).outcome,
        StageOutcome.fail,
      );
    });

    test('Host und Altwert vorhanden: die höhere Version zählt (Rückschritt '
        'gegen den Altwert)', () async {
      final f = TinfoilFixture(tag: 'v0.0.160');
      await f.floors.save(
        floorKey,
        ReleaseFloor(
          version: ReleaseVersion.tryParse('v0.0.150')!,
          integratedTime: 1,
        ),
      );
      await f.floors.save(
        'altprofil',
        ReleaseFloor(
          version: ReleaseVersion.tryParse('v0.0.170')!,
          integratedTime: 1,
        ),
      );
      final r = await f.verifier(profileId: 'altprofil').attest();
      expect(r.status, AttestationStatus.red);
      final stage = stageOf(r, AttestationStage.releaseFloor);
      expect(stage.outcome, StageOutcome.fail);
      expect(stage.code, StageResult.releaseRollback);
    });

    test(
      'Host und Altwert, gleiche Version: die spätere Signierzeit zählt',
      () async {
        final f = TinfoilFixture(tag: 'v0.0.158');
        final v = ReleaseVersion.tryParse('v0.0.158')!;
        await f.floors.save(
          floorKey,
          ReleaseFloor(version: v, integratedTime: 1),
        );
        await f.floors.save(
          'altprofil',
          ReleaseFloor(version: v, integratedTime: 4000000000),
        );
        final r = await f.verifier(profileId: 'altprofil').attest();
        expect(r.status, AttestationStatus.red);
        expect(
          stageOf(r, AttestationStage.releaseFloor).code,
          StageResult.releaseRollback,
        );
      },
    );

    test('mehrere gültige Bundles: die späteste Signierzeit zählt, nicht die '
        'Reihenfolge', () async {
      final f = TinfoilFixture(tag: 'v0.0.158', integratedTime: 1789000500)
        ..bundles = 2;
      // Das erste Bundle ist älter, das zweite neuer (gleiche Version).
      f.sigstore.perBundle = (b) => b.contains('"n":0')
          ? f.sigstore.verdict
          : const SigstoreVerdict(
              dsseOk: true,
              chainOk: true,
              identityOk: true,
              rekorOk: true,
              measurementOk: true,
              snpMeasurementHex: TinfoilFixture.measurement,
              releaseTag: 'v0.0.158',
              integratedTime: 1789000900,
            );
      expect((await f.verifier().attest()).status, AttestationStatus.green);
      expect((await f.floors.load(floorKey))!.integratedTime, 1789000900);
      // Dieselbe Version, nun nur noch mit der mittleren Zeit: kein Aussperren
      // durch die Reihenfolge, aber die spätere Zeit bleibt die Untergrenze.
      final r = await f.verifier().attest();
      expect(r.status, AttestationStatus.green, reason: '${r.stages}');
      expect((await f.floors.load(floorKey))!.integratedTime, 1789000900);
    });

    test('eine rote Prüfung hebt die Untergrenze nicht an', () async {
      final f = TinfoilFixture(tag: 'v0.0.158');
      await f.verifier().attest();
      f
        ..tag = 'v0.0.200'
        ..sigstoreGreen();
      f.snp.verdict = _verdict(signatureOk: false);
      expect((await f.verifier().attest()).status, AttestationStatus.red);
      expect((await f.floors.load(floorKey))!.version.toString(), 'v0.0.158');
    });

    test(
      'beschädigte Untergrenze: rot, keine Sitzung, nichts gespeichert',
      () async {
        final f = TinfoilFixture();
        final r = await f.verifier(floorStore: DamagedFloorStore()).attest();
        expect(r.status, AttestationStatus.red);
        final stage = stageOf(r, AttestationStage.releaseFloor);
        expect(stage.outcome, StageOutcome.fail);
        expect(stage.detail, contains('beschädigt'));
        expect(stage.code, StageResult.releaseFloorCorrupt);
        expect(r.session, isNull);
      },
    );
  });

  group('AMD-Zertifikate (KDS)', () {
    int kdsRequests(TinfoilFixture f) =>
        f.requests.where((r) => r.url.host == 'kdsintf.amd.com').length;

    test('ein neuer Verifier fragt AMD nicht erneut (Cache)', () async {
      final f = TinfoilFixture();
      final cache = InMemoryKdsCache();
      expect(
        (await f.verifier(kdsCache: cache).attest()).status,
        AttestationStatus.green,
      );
      final first = kdsRequests(f);
      expect(first, greaterThan(0));
      final r = await f.verifier(kdsCache: cache).attest();
      expect(r.status, AttestationStatus.green);
      expect(kdsRequests(f), first);
    });

    test('ein Eintrag, der die Kette nicht besteht, wird verworfen; danach '
        'frisch von AMD', () async {
      final f = TinfoilFixture();
      final cache = InMemoryKdsCache();
      expect(
        (await f.verifier(kdsCache: cache).attest()).status,
        AttestationStatus.green,
      );
      final first = kdsRequests(f);
      f.snp.verdict = _verdict(chainOk: false);
      final bad = await f.verifier(kdsCache: cache).attest();
      expect(bad.status, AttestationStatus.red);
      expect(kdsRequests(f), first, reason: 'der Eintrag kam aus dem Cache');
      f.snp.verdict = _verdict();
      final again = await f.verifier(kdsCache: cache).attest();
      expect(again.status, AttestationStatus.green);
      expect(kdsRequests(f), greaterThan(first), reason: 'neu von AMD geholt');
    });

    test('ein Cache, der wirft, ist nur ein Fehlschlag', () async {
      final f = TinfoilFixture();
      final r = await f.verifier(kdsCache: _ThrowingCache()).attest();
      expect(r.status, AttestationStatus.green);
    });
  });

  group('ReleaseVersion / ReleaseFloor', () {
    test('Ordnung und Parser', () {
      final v = ReleaseVersion.tryParse;
      expect(v('v0.0.158')!.compareTo(v('v0.0.159')!), lessThan(0));
      expect(v('v0.1.0')!.compareTo(v('v0.0.999')!), greaterThan(0));
      expect(v('1.0.0'), v('v1.0.0'));
      for (final bad in [
        '',
        'latest',
        'v1.2',
        'v1.2.3-rc1',
        'v1.2.3.4',
        'v1.a.3',
      ]) {
        expect(v(bad), isNull, reason: bad);
      }
    });

    test('JSON Rundlauf, kaputte Daten werfen FormatException', () {
      final f = ReleaseFloor(
        version: ReleaseVersion.tryParse('v0.0.158')!,
        integratedTime: 5,
      );
      expect(ReleaseFloor.fromJson(f.toJson()), f);
      expect(
        () => ReleaseFloor.fromJson({'version': 'x'}),
        throwsFormatException,
      );
      expect(
        () =>
            ReleaseFloor.fromJson({'version': 'v1.0.0', 'integratedTime': -1}),
        throwsFormatException,
      );
    });
  });
}

final class _ThrowingCache implements KdsCache {
  @override
  Future<KdsEntry?> load(String key) => throw StateError('x');

  @override
  Future<void> save(String key, KdsEntry entry) => throw StateError('x');

  @override
  Future<void> remove(String key) => throw StateError('x');
}
