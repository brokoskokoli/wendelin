import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../../common/http_settings.dart';
import '../../common/http_transport.dart';
import '../../common/redactor.dart';
import '../attestation_crypto.dart';
import '../attestation_pin_store.dart';
import '../attestation_policy.dart';
import '../attestation_types.dart';
import '../codec.dart';
import '../session_channel.dart';
import '../sigstore_crypto.dart';
import '../snp_crypto.dart';
import '../tls_pin_gate.dart';
import 'ehbp_crypto.dart';
import 'release_floor.dart';

/// Fixed decisions of the Tinfoil attestation (ADR 0020).
abstract final class TinfoilPolicy {
  /// Repository whose signed release the router measurement must belong to.
  static const repo = 'tinfoilsh/confidential-model-router';

  /// Lowest accepted `reported_tcb`: set one step below the recording
  /// (bootloader 10, SNP 23, microcode 84) on purpose, so a firmware
  /// update of AMD does not lock the user out while a rollback to a
  /// vulnerable firmware is refused. TEE SPL is not constrained (0).
  static const minTcb = SnpTcb(bootloader: 9, tee: 0, snp: 22, microcode: 80);

  /// [minTcb] as the policy of `SnpCrypto.verify`.
  static const snpPolicy = SnpPolicy(minTcb: minTcb);

  /// AMD products whose ARK is pinned and whose TCB layout is supported
  /// (Turin follows, WP76 notes), in the order they are tried.
  static const products = ['Genoa', 'Milan'];

  /// Document format of `/.well-known/tinfoil-attestation`.
  static const attestationFormat =
      'https://tinfoil.sh/predicate/sev-snp-guest/v2';

  /// Largest accepted SNP report (v3 is 1184 bytes).
  static const maxReportBytes = 4096;
}

/// [AttestationVerifier] for the Tinfoil router (ADR 0020): AMD SEV-SNP of
/// the router CVM, its measurement against the signed GitHub release
/// (Sigstore), the TLS pin and the HPKE key, both only from the attested
/// `report_data`.
///
/// Stages (all must pass, fail-closed): `snp.report` (parse, VCEK matches,
/// ECDSA P-384), `snp.chain` (VCEK -> ASK -> pinned ARK), `snp.policy`
/// (no debug, VMPL 0, [TinfoilPolicy.minTcb]), `tls.spki` (certificate of
/// the connection = `report_data[0..32]`), `bind.hpke` (the key the router
/// serves = `report_data[32..64]`), `sigstore.release` and `measurement`
/// (the report measurement is the one of the **latest** signed release),
/// `release.floor` (no release older than the highest ever seen, K59),
/// `e2ee.key`. `receipt.none` is information: Tinfoil issues no receipt per
/// answer ([ReceiptFreeVerifier]).
///
/// Nothing is trusted from the network beyond signatures: KDS and GitHub
/// answers are verified in Rust; the router only delivers bytes that must
/// match the attested report.
final class TinfoilVerifier
    implements AttestationVerifier, ReceiptFreeVerifier {
  /// Creates the verifier. [baseUrl] is the profile base (`…/v1`); the
  /// documents live under `/.well-known/` of the same host.
  TinfoilVerifier({
    required this.crypto,
    required this.snp,
    required this.sigstore,
    required this.ehbp,
    required this.floors,
    required this.baseUrl,
    required this.profileId,
    required http.Client client,
    http.Client? externalClient,
    this.settings = const HttpSettings(),
    this.policy = const AttestationPolicy(),
    this.pins,
    this.tlsPin,
    this.sessionTtl = const Duration(minutes: 30),
    this.repo = TinfoilPolicy.repo,
    this.kdsBase = 'https://kdsintf.amd.com',
    this.githubApi = 'https://api.github.com',
    this.githubWeb = 'https://github.com',
  }) : _router = HttpTransport(
         client: client,
         settings: settings,
         label: 'Attestierung',
         redactor: Redactor(),
       ),
       _external = HttpTransport(
         client: externalClient ?? client,
         settings: settings,
         label: 'Attestierung',
         redactor: Redactor(),
       );

  /// Hash functions.
  final AttestationCrypto crypto;

  /// SEV-SNP verification (Rust).
  final SnpCrypto snp;

  /// Sigstore verification (Rust).
  final SigstoreCrypto sigstore;

  /// EHBP key configuration binding (Rust).
  final EhbpCrypto ehbp;

  /// Highest release seen per profile (K59).
  final ReleaseFloorStore floors;

  /// Profile base URL.
  final Uri baseUrl;

  /// Provider profile id (key of pin and floor).
  final String profileId;

  /// Timeouts, clock and log.
  final HttpSettings settings;

  /// Stage results -> status.
  final AttestationPolicy policy;

  /// Pin store; `null` = no pinning.
  final AttestationPinStore? pins;

  /// Pin state shared with the enforcing client (WP61).
  final TlsPinGate? tlsPin;

  /// How long an attested session is used.
  final Duration sessionTtl;

  /// GitHub repository of the router releases.
  final String repo;

  /// Base URL of the AMD key distribution service.
  final String kdsBase;

  /// Base URL of the GitHub API.
  final String githubApi;

  /// Base URL of github.com (release downloads).
  final String githubWeb;

  /// Talks to the router: the connection is measured by [tlsPin].
  final HttpTransport _router;

  /// Talks to AMD and GitHub: never over the measured connection.
  final HttpTransport _external;

  String? _product;
  final Map<String, ({Uint8List vcek, String chain, String product})> _kds = {};
  final Map<String, ({String digest, List<String> bundles})> _releases = {};

  @override
  String get noReceiptNote =>
      'Keine Quittung je Antwort: Tinfoil stellt keine aus. Die Antwort ist '
      'nur über die Verschlüsselung an diese Anfrage gebunden.';

  Uri _wellKnown(String name) => baseUrl.replace(
    path: '/.well-known/$name',
    queryParameters: null,
    fragment: '',
  );

  @override
  Future<AttestationResult> attest() async {
    final gate = tlsPin
      ?..expect(null)
      ..resetObserved();
    final now = settings.clock.now();

    final docs = await _documents();
    final failure = docs.failure;
    if (failure != null) return _failed(failure);
    final report = docs.report!;
    final keyConfig = docs.keyConfig!;
    // Measured on the connection that delivered the documents.
    final observed = gate?.observed;

    final SnpReportInfo info;
    final Uint8List reportData;
    try {
      info = snp.reportInfo(report);
      reportData = AttestCodec.unhex(info.reportDataHex);
      if (reportData.length != 64) throw const FormatException('report_data');
    } on Object {
      return _failed(const [
        StageResult.fail(AttestationStage.snpReport, 'Report nicht lesbar'),
      ]);
    }

    // --- binding of the key configuration to report_data --------------
    EhbpBinding? binding;
    try {
      binding = ehbp.bindKeyConfig(keyConfig, reportData);
    } on E2eeCryptoException {
      binding = null;
    }
    final hpkeKey = binding != null && keyConfig.length == 41
        ? Uint8List.fromList(keyConfig.sublist(3, 35))
        : Uint8List.fromList(reportData.sublist(32));

    // --- AMD collateral and signed release, in parallel ----------------
    final kdsFuture = _collateral(info);
    final releaseFuture = _release(info.measurementHex);
    final kds = await kdsFuture;
    final release = await releaseFuture;

    final stages = <StageResult>[];
    var snpOk = false;
    final kdsProblem = kds.problem;
    if (kdsProblem != null) {
      stages.add(kdsProblem);
    } else {
      final expectedTls = gate == null
          ? Uint8List.fromList(reportData.sublist(0, 32))
          : (observed == null ? Uint8List(32) : AttestCodec.unhex(observed));
      final SnpVerdict verdict;
      try {
        verdict = await snp.verify(
          report: report,
          vcekDer: kds.vcek!,
          chainPem: kds.chain!,
          now: now,
          policy: TinfoilPolicy.snpPolicy,
          tlsSpkiSha256: expectedTls,
          hpkeKey: hpkeKey,
        );
      } on Object {
        return _failed(const [
          StageResult.fail(
            AttestationStage.snpReport,
            'Prüfung fehlgeschlagen',
          ),
        ]);
      }
      snpOk = verdict.allOk;
      stages.addAll(_snpStages(verdict, info, gate != null, observed));
    }
    stages.add(
      binding != null
          ? const StageResult.pass(
              AttestationStage.bindHpke,
              'Schlüssel des Routers = report_data',
            )
          : const StageResult.fail(
              AttestationStage.bindHpke,
              'Schlüssel des Routers gehört nicht zum Report',
            ),
    );

    var releaseOk = false;
    ReleaseFloor? newFloor;
    final releaseProblem = release.problem;
    if (releaseProblem != null) {
      stages.add(releaseProblem);
    } else {
      final verdict = release.verdict!;
      releaseOk = verdict.allOk;
      stages.addAll(_releaseStages(verdict, release.tag!));
      if (verdict.allOk) {
        final (floorStage, floor) = await _floorStage(
          release.tag!,
          verdict.integratedTime,
        );
        stages.add(floorStage);
        newFloor = floor;
      }
    }
    stages
      ..add(
        binding != null
            ? const StageResult.pass(
                AttestationStage.e2eeKey,
                'HPKE X25519, aus dem Report',
              )
            : const StageResult.fail(
                AttestationStage.e2eeKey,
                'Kein geprüfter Verschlüsselungsschlüssel',
              ),
      )
      ..add(
        StageResult(
          AttestationStage.noReceipt,
          StageOutcome.info,
          noReceiptNote,
        ),
      );

    var status = policy.sessionStatus(stages);
    final complete = snpOk && releaseOk && binding != null && newFloor != null;
    if (status == AttestationStatus.green && !complete) {
      // Defence in depth: never green unless every part is.
      stages.add(
        const StageResult.fail(
          AttestationStage.snpReport,
          'Prüfung unvollständig',
        ),
      );
      status = AttestationStatus.red;
    }
    if (status != AttestationStatus.green) return _failed(stages);

    gate?.expect(AttestCodec.hex(binding!.tlsSpkiSha256));
    final session = _sessionOf(
      reportData: reportData,
      keyConfig: keyConfig,
      hpkeKey: hpkeKey,
      info: info,
      tag: release.tag,
      now: now,
    );
    await floors.save(profileId, newFloor!);
    return AttestationResult(
      status: status,
      stages: stages,
      session: session,
      notes: policy.notes(stages),
      pinChange: await _pin(session),
    );
  }

  /// Report and key configuration of the router, or the failed stages.
  Future<_Docs> _documents() async {
    try {
      final got = await Future.wait([
        _router.getJson(
          _wellKnown('tinfoil-attestation'),
          const {},
          onHttpError: _status,
        ),
        _router.getBytes(
          _wellKnown('hpke-keys'),
          const {},
          maxBytes: 1024,
          onHttpError: _status,
        ),
      ]);
      return _Docs(
        report: _reportOf(got[0] as Map<String, Object?>),
        keyConfig: got[1] as Uint8List,
      );
    } on FormatException catch (e) {
      return _Docs.failed([
        StageResult.fail(AttestationStage.snpReport, e.message),
      ]);
    } on MalformedResponseException {
      return _Docs.failed(const [
        StageResult.fail(AttestationStage.snpReport, 'Antwort nicht lesbar'),
      ]);
    } on ProviderException {
      return _Docs.failed(const [
        StageResult(
          AttestationStage.snpReport,
          StageOutcome.unavailable,
          'Attestierung nicht abrufbar',
        ),
      ]);
    }
  }

  AttestedSession _sessionOf({
    required Uint8List reportData,
    required Uint8List keyConfig,
    required Uint8List hpkeKey,
    required SnpReportInfo info,
    required String? tag,
    required DateTime now,
  }) => AttestedSession(
    keysetDigest: AttestCodec.hex(crypto.sha256(reportData)),
    notAfter: now.add(sessionTtl),
    receiptKeys: const {},
    repoCommit: tag,
    composeHash: info.measurementHex,
    attestedAt: now,
    workloadId: null,
    e2eeKey: E2eeKey(
      keyId: 'hpke',
      algo: 'X25519-HKDF-SHA256',
      publicKey: hpkeKey,
    ),
    ehbpKeyConfig: keyConfig,
    reportData: reportData,
  );

  AttestationResult _failed(List<StageResult> stages) =>
      AttestationResult(status: policy.sessionStatus(stages), stages: stages);

  ProviderException _status(int status, String body, Duration? retry) =>
      ServerException('Attestierung: HTTP $status', statusCode: status);

  /// The SNP report out of `{format, body}` (body = base64 of gzip).
  Uint8List _reportOf(Map<String, Object?> doc) {
    if (doc['format'] != TinfoilPolicy.attestationFormat) {
      throw const FormatException('Dokumentformat unbekannt');
    }
    final body = doc['body'];
    if (body is! String) throw const FormatException('Dokument ohne Report');
    final Uint8List zipped;
    try {
      zipped = base64.decode(body);
    } on FormatException {
      throw const FormatException('Report nicht lesbar');
    }
    if (zipped.length > TinfoilPolicy.maxReportBytes) {
      throw const FormatException('Report zu groß');
    }
    final out = BytesBuilder(copy: false);
    final sink = _CappedSink(out, TinfoilPolicy.maxReportBytes);
    try {
      GZipCodec().decoder.startChunkedConversion(sink)
        ..add(zipped)
        ..close();
    } on Object {
      throw const FormatException('Report nicht lesbar');
    }
    return out.takeBytes();
  }

  // --- AMD KDS --------------------------------------------------------

  Future<_Kds> _collateral(SnpReportInfo info) async {
    final chip = info.chipIdHex.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{128}$').hasMatch(chip)) {
      return _Kds.problem(
        const StageResult.fail(
          AttestationStage.snpChain,
          'Kennung des Prozessors ungültig',
        ),
      );
    }
    final t = info.reportedTcb;
    final query =
        'blSPL=${t.bootloader}&teeSPL=${t.tee}&snpSPL=${t.snp}'
        '&ucodeSPL=${t.microcode}';
    final key = '$chip?$query';
    final cached = _kds[key];
    if (cached != null) return _Kds(cached.vcek, cached.chain);
    final products = [
      ?_product,
      for (final p in TinfoilPolicy.products)
        if (p != _product) p,
    ];
    for (final product in products) {
      try {
        final vcek = await _external.getBytes(
          Uri.parse('$kdsBase/vcek/v1/$product/$chip?$query'),
          const {},
          maxBytes: 8192,
          onHttpError: _status,
        );
        final chain = utf8.decode(
          await _external.getBytes(
            Uri.parse('$kdsBase/vcek/v1/$product/cert_chain'),
            const {},
            maxBytes: 32768,
            onHttpError: _status,
          ),
          allowMalformed: true,
        );
        _product = product;
        _kds[key] = (vcek: vcek, chain: chain, product: product);
        return _Kds(vcek, chain);
      } on ServerException catch (e) {
        // „Not found“ for this product: the chip belongs to another one.
        if (e.statusCode == 404 || e.statusCode == 400) continue;
        return _Kds.problem(_unavailable(AttestationStage.snpChain));
      } on MalformedResponseException {
        return _Kds.problem(
          const StageResult.fail(
            AttestationStage.snpChain,
            'Antwort des AMD-Schlüsseldienstes unlesbar',
          ),
        );
      } on ProviderException {
        return _Kds.problem(_unavailable(AttestationStage.snpChain));
      }
    }
    return _Kds.problem(
      const StageResult.fail(
        AttestationStage.snpChain,
        'Prozessor beim AMD-Schlüsseldienst unbekannt',
      ),
    );
  }

  StageResult _unavailable(AttestationStage stage) => StageResult(
    stage,
    StageOutcome.unavailable,
    'Quelle nicht abrufbar (${stage.id})',
  );

  List<StageResult> _snpStages(
    SnpVerdict v,
    SnpReportInfo info,
    bool gated,
    String? observed,
  ) {
    final err = v.errors.isEmpty ? null : v.errors.join('; ');
    StageResult stage(AttestationStage s, bool ok, String pass, String fail) =>
        ok && err == null
        ? StageResult.pass(s, pass)
        : StageResult.fail(s, err ?? fail);
    final tlsOk = v.tlsBound && gated && observed != null;
    return [
      stage(
        AttestationStage.snpReport,
        v.reportOk && v.vcekMatchesReport && v.signatureOk,
        'Version ${info.version}, Signatur gültig',
        'Report, Zertifikat oder Signatur ungültig',
      ),
      stage(
        AttestationStage.snpChain,
        v.chainOk,
        'AMD ${v.product ?? ''} (ARK gepinnt)'.replaceAll('  ', ' '),
        'Zertifikatskette nicht gültig',
      ),
      stage(
        AttestationStage.snpPolicy,
        v.policyOk,
        'TCB ${info.reportedTcb}, Mindestens ${TinfoilPolicy.minTcb}',
        'Richtlinie nicht erfüllt',
      ),
      if (!gated)
        const StageResult(
          AttestationStage.tlsSpki,
          StageOutcome.info,
          'Zertifikat der Verbindung nicht geprüft',
        )
      else if (observed == null)
        const StageResult.fail(
          AttestationStage.tlsSpki,
          'Zertifikat der Verbindung nicht messbar',
        )
      else if (!tlsOk)
        const StageResult.fail(
          AttestationStage.tlsSpki,
          'SPKI der Verbindung weicht vom Report ab',
        )
      else
        const StageResult.pass(AttestationStage.tlsSpki, 'Verbindung geprüft'),
      ?(v.hpkeBound
          ? null
          : const StageResult.fail(
              AttestationStage.bindHpke,
              'HPKE-Schlüssel weicht vom Report ab',
            )),
    ];
  }

  // --- Sigstore ---------------------------------------------------------

  Future<_Release> _release(String measurementHex) async {
    final String tag;
    try {
      final latest = await _external.getJson(
        Uri.parse('$githubApi/repos/$repo/releases/latest'),
        _githubHeaders,
        onHttpError: _status,
      );
      final name = latest['tag_name'];
      if (name is! String || ReleaseVersion.tryParse(name) == null) {
        return _Release.problem(
          const StageResult.fail(
            AttestationStage.sigstoreRelease,
            'Release-Version nicht lesbar',
          ),
        );
      }
      tag = name;
    } on MalformedResponseException {
      return _Release.problem(
        const StageResult.fail(
          AttestationStage.sigstoreRelease,
          'Release-Angabe unlesbar',
        ),
      );
    } on ProviderException {
      return _Release.problem(_unavailable(AttestationStage.sigstoreRelease));
    }
    var cached = _releases[tag];
    if (cached == null) {
      try {
        final hash = utf8
            .decode(
              await _external.getBytes(
                Uri.parse(
                  '$githubWeb/$repo/releases/download/$tag/tinfoil.hash',
                ),
                const {},
                maxBytes: 512,
                onHttpError: _status,
              ),
              allowMalformed: true,
            )
            .trim()
            .toLowerCase();
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          return _Release.problem(
            const StageResult.fail(
              AttestationStage.sigstoreRelease,
              'tinfoil.hash unlesbar',
            ),
          );
        }
        final doc = await _external.getJson(
          Uri.parse('$githubApi/repos/$repo/attestations/sha256:$hash'),
          _githubHeaders,
          onHttpError: _status,
        );
        final list = doc['attestations'];
        final bundles = <String>[
          if (list is List<Object?>)
            for (final a in list.take(5))
              if (a is Map<String, Object?> && a['bundle'] is Map)
                jsonEncode(a['bundle']),
        ];
        if (bundles.isEmpty) {
          return _Release.problem(
            const StageResult.fail(
              AttestationStage.sigstoreRelease,
              'Kein Sigstore-Nachweis zum Release',
            ),
          );
        }
        cached = (digest: hash, bundles: bundles);
        _releases[tag] = cached;
      } on MalformedResponseException {
        return _Release.problem(
          const StageResult.fail(
            AttestationStage.sigstoreRelease,
            'Release-Nachweis unlesbar',
          ),
        );
      } on ProviderException {
        return _Release.problem(_unavailable(AttestationStage.sigstoreRelease));
      }
    }
    // The signatures hold offline; the first bundle that verifies wins, else
    // the verdict of the first one explains the failure.
    SigstoreVerdict? first;
    for (final bundle in cached.bundles) {
      final SigstoreVerdict v;
      try {
        v = await sigstore.verifyRelease(
          bundleJson: bundle,
          repo: repo,
          tag: tag,
          digestHex: cached.digest,
          reportMeasurementHex: measurementHex,
        );
      } on Object {
        return _Release.problem(
          const StageResult.fail(
            AttestationStage.sigstoreRelease,
            'Prüfung des Releases fehlgeschlagen',
          ),
        );
      }
      first ??= v;
      if (v.allOk) return _Release(tag: tag, verdict: v);
    }
    return _Release(tag: tag, verdict: first!);
  }

  Map<String, String> get _githubHeaders => const {
    'accept': 'application/vnd.github+json',
    'x-github-api-version': '2022-11-28',
  };

  List<StageResult> _releaseStages(SigstoreVerdict v, String tag) {
    final err = v.errors.isEmpty ? null : v.errors.join('; ');
    final signed = v.dsseOk && v.chainOk && v.identityOk && v.rekorOk;
    return [
      signed && err == null
          ? StageResult.pass(AttestationStage.sigstoreRelease, 'Release $tag')
          : StageResult.fail(
              AttestationStage.sigstoreRelease,
              err ?? 'Signatur des Releases ungültig',
            ),
      v.measurementOk
          ? StageResult.pass(AttestationStage.measurement, 'Release $tag')
          : StageResult.fail(
              AttestationStage.measurement,
              'Messwert des Routers gehört nicht zum neuesten signierten '
              'Release $tag (Update des Anbieters? Später erneut prüfen)',
            ),
    ];
  }

  /// Downgrade protection (K59): a release older than the highest one ever
  /// verified for this profile is refused, replayed old data included.
  Future<(StageResult, ReleaseFloor?)> _floorStage(String tag, int time) async {
    const s = AttestationStage.releaseFloor;
    final version = ReleaseVersion.tryParse(tag);
    if (version == null) {
      return (const StageResult.fail(s, 'Release-Version nicht lesbar'), null);
    }
    final floor = await _loadFloor();
    if (floor != null && floor.rejects(version, time)) {
      return (
        StageResult.fail(
          s,
          'Release $version ist älter als das bereits gesehene '
          '${floor.version} (Rückschritt abgelehnt)',
        ),
        null,
      );
    }
    // Only ever raised: the same release keeps its first signing time.
    final higher =
        floor == null ||
        version.compareTo(floor.version) > 0 ||
        (version == floor.version && time > floor.integratedTime);
    final next = higher
        ? ReleaseFloor(version: version, integratedTime: time)
        : floor;
    return (StageResult.pass(s, 'Release $version'), next);
  }

  Future<ReleaseFloor?> _loadFloor() async {
    try {
      return await floors.load(profileId);
    } on FormatException {
      return null; // A damaged floor counts as none: the next check sets it.
    }
  }

  Future<PinChange> _pin(AttestedSession s) async {
    final store = pins;
    if (store == null) return PinChange.none;
    final pin = AttestationPin(
      keysetDigest: s.keysetDigest,
      composeHash: s.composeHash,
      repoCommit: s.repoCommit,
      pinnedAt: s.attestedAt,
    );
    final old = await store.load(profileId);
    if (old == null) {
      await store.save(profileId, pin);
      return PinChange.first;
    }
    if (!old.changedBy(pin)) return PinChange.none;
    await store.save(profileId, pin);
    return PinChange.changed;
  }

  @override
  Future<ReceiptResult> verifyReceipt(
    ReceiptRef ref,
    Uint8List requestBytes,
    Uint8List responseBytes,
  ) async => ReceiptResult(
    stages: [
      StageResult(AttestationStage.noReceipt, StageOutcome.info, noReceiptNote),
    ],
    status: AttestationStatus.unconfirmed,
  );
}

/// Collects at most [limit] bytes; more throws (decompression bomb).
final class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._out, this.limit);

  final BytesBuilder _out;
  final int limit;

  @override
  void add(List<int> data) {
    _out.add(data);
    if (_out.length > limit) throw const FormatException('zu groß');
  }

  @override
  void close() {}
}

final class _Kds {
  _Kds(this.vcek, this.chain) : problem = null;
  _Kds.problem(this.problem) : vcek = null, chain = null;

  final Uint8List? vcek;
  final String? chain;
  final StageResult? problem;
}

final class _Release {
  _Release({required String this.tag, required SigstoreVerdict this.verdict})
    : problem = null;
  _Release.problem(this.problem) : tag = null, verdict = null;

  final String? tag;
  final SigstoreVerdict? verdict;
  final StageResult? problem;
}

/// The documents of the router, or the stages of the failure.
final class _Docs {
  _Docs({required Uint8List this.report, required Uint8List this.keyConfig})
    : failure = null;
  _Docs.failed(List<StageResult> this.failure)
    : report = null,
      keyConfig = null;

  final Uint8List? report;
  final Uint8List? keyConfig;
  final List<StageResult>? failure;
}
