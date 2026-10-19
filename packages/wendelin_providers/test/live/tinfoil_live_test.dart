@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

// Live-Test gegen Tinfoil, sparsam: gpt-oss-120b, kleines max_tokens, höchstens
// zwei Chat-Anfragen. Der Key kommt nur aus der Umgebung und wird nie ausgegeben.
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped test/live/tinfoil_live_test.dart
//
// Echt sind: Attestierungsdokument und Schlüsselkonfiguration des Routers, AMD KDS
// (VCEK, Kette) und GitHub (Release, Sigstore-Bundle), die Bindung von TLS-Pin und
// HPKE-Schlüssel allein an `report_data`, EHBP mit Werkzeugen und Streaming gegen den
// echten Dienst. Die Signaturketten (AMD, Sigstore) prüft in Dart nur das Rust-Modul,
// das hier nicht läuft: Report-Felder und Bindungen liest `_LiveSnp` selbst aus dem
// Report, `_LiveSigstore` übernimmt die Angaben des Reports. Die echte Prüfung gegen
// aufgezeichnete Daten laufen in native/attest/tests (snp.rs, sigstore.rs, ehbp_live.rs).

const _model = 'gpt-oss-120b';
final _base = Uri.parse('https://inference.tinfoil.sh/v1');
final _key = Platform.environment['TINFOIL_API_KEY'];

const _tool = ToolSpec(
  name: 'timer__set',
  description: 'Stellt einen Timer in Minuten.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'minutes': {'type': 'integer', 'description': 'Minuten'},
    },
    'required': ['minutes'],
  },
);

bool _skip() {
  final key = _key;
  if (key == null || key.isEmpty) {
    markTestSkipped('TINFOIL_API_KEY nicht gesetzt');
    return true;
  }
  return false;
}

/// SNP-Felder und Bindungen aus dem echten Report (Offsets AMD SEV-SNP ABI).
final class _LiveSnp implements SnpCrypto {
  @override
  SnpReportInfo reportInfo(Uint8List r) {
    final v = ByteData.sublistView(r);
    return SnpReportInfo(
      version: v.getUint32(0, Endian.little),
      vmpl: v.getUint32(0x30, Endian.little),
      reportedTcb: SnpTcb(
        bootloader: r[0x180],
        tee: r[0x181],
        snp: r[0x186],
        microcode: r[0x187],
      ),
      measurementHex: AttestCodec.hex(r.sublist(0x90, 0xC0)),
      reportDataHex: AttestCodec.hex(r.sublist(0x50, 0x90)),
      chipIdHex: AttestCodec.hex(r.sublist(0x1A0, 0x1E0)),
    );
  }

  @override
  Future<SnpVerdict> verify({
    required Uint8List report,
    required Uint8List vcekDer,
    required String chainPem,
    required DateTime now,
    required SnpPolicy policy,
    required Uint8List tlsSpkiSha256,
    required Uint8List hpkeKey,
  }) async {
    final info = reportInfo(report);
    final t = info.reportedTcb;
    final m = policy.minTcb;
    final data = report.sublist(0x50, 0x90);
    bool same(Uint8List a, Uint8List b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    return SnpVerdict(
      reportOk: info.version >= 2 && info.vmpl == 0,
      chainOk: chainPem.contains('BEGIN CERTIFICATE') && vcekDer.isNotEmpty,
      vcekMatchesReport: vcekDer.isNotEmpty,
      signatureOk: true,
      policyOk:
          t.bootloader >= m.bootloader &&
          t.tee >= m.tee &&
          t.snp >= m.snp &&
          t.microcode >= m.microcode,
      tlsBound: same(data.sublist(0, 32), tlsSpkiSha256),
      hpkeBound: same(data.sublist(32, 64), hpkeKey),
      info: info,
    );
  }
}

final class _LiveSigstore implements SigstoreCrypto {
  @override
  Future<SigstoreVerdict> verifyRelease({
    required String bundleJson,
    required String repo,
    required String tag,
    required String digestHex,
    required String reportMeasurementHex,
  }) async => SigstoreVerdict(
    dsseOk: bundleJson.isNotEmpty,
    chainOk: true,
    identityOk: repo == 'tinfoilsh/confidential-model-router',
    rekorOk: true,
    measurementOk: true,
    snpMeasurementHex: reportMeasurementHex,
    releaseTag: tag,
    integratedTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

({AttestedProvider provider, TinfoilVerifier verifier}) _build(
  http.Client client,
) {
  final ehbp = EhbpReferenceCrypto();
  const settings = HttpSettings();
  final gate = TlsPinGate(spkiSha256: FakeAttestationCrypto().sha256);
  final verifier = TinfoilVerifier(
    crypto: FakeAttestationCrypto(),
    snp: _LiveSnp(),
    sigstore: _LiveSigstore(),
    ehbp: ehbp,
    floors: InMemoryReleaseFloorStore(),
    baseUrl: _base,
    profileId: 'tinfoil-live',
    client: client,
    externalClient: client,
    settings: settings,
  );
  final provider = AttestedProvider(
    inner: OpenAiChatAdapter(
      baseUrl: _base,
      credentials: Credentials.apiKey(_key!, style: ApiKeyStyle.bearer),
      defaultModel: _model,
      client: client,
      settings: settings,
      wireCodec: TinfoilEhbpChannel(crypto: ehbp, tlsPin: gate),
    ),
    verifier: verifier,
    profileId: 'tinfoil-live',
    requireUpstreamEnforced: false,
    settings: settings,
  );
  return (provider: provider, verifier: verifier);
}

ChatRequest _request(List<Message> messages) => ChatRequest(
  systemPrompt: 'Du bist Wendelin. Nutze Werkzeuge, wenn sie passen.',
  messages: messages,
  tools: [_tool],
  model: _model,
  maxTokens: 200,
);

void main() {
  // One verifier for both tests: AMD's KDS answers a second request for the
  // same chip within seconds with 429, the verifier caches its documents.
  final client = http.Client();
  tearDownAll(client.close);
  late final built = _build(client);

  test('Attestierung: Report, KDS, Release, Bindung aus report_data', () async {
    if (_skip()) return;
    final result = await built.verifier.attest();
    // ignore: avoid_print
    print('Stufen: ${result.stages}');
    expect(result.stages.where((s) => s.outcome == StageOutcome.fail), isEmpty);
    expect(result.session!.ehbpKeyConfig, isNotNull);
    expect(result.session!.reportData, hasLength(64));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'EHBP-Chat mit Werkzeugaufruf (Streaming), zweiter Zug mit Ergebnis',
    () async {
      if (_skip()) return;
      final client = http.Client();
      final provider = _build(client).provider;
      final first = [Message.user('Stell einen Timer auf 12 Minuten.')];
      final events = await provider.chat(_request(first)).toList();
      final errors = events.whereType<ErrorEvent>().toList();
      expect(
        errors,
        isEmpty,
        reason: '${errors.map((e) => e.error.runtimeType)}',
      );
      final call = events.whereType<ToolCallComplete>().single.call;
      expect(call.name, 'timer__set');
      expect(jsonDecode(call.argumentsJson), {'minutes': 12});

      final second = await provider
          .chat(
            _request([
              ...first,
              Message.assistant([call]),
              Message.toolResults([
                ToolResultBlock(
                  callId: call.id,
                  content: [const TextBlock('Timer läuft: 12 Minuten.')],
                ),
              ]),
            ]),
          )
          .toList();
      expect(second.whereType<ErrorEvent>(), isEmpty);
      expect(
        second.whereType<TextDelta>().map((e) => e.text).join(),
        isNotEmpty,
      );
      final report = await provider.pendingReport();
      // ignore: avoid_print
      print('Antwort: ${report?.status} ${report?.detail ?? ''}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
