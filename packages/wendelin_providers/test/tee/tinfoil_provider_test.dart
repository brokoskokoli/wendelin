import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tinfoil_support.dart';

const _sse =
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":'
    '{"role":"assistant","content":"Hallo"}}]}\n\n'
    'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{},'
    '"finish_reason":"stop"}],"usage":{"prompt_tokens":3,'
    '"completion_tokens":1}}\n\n'
    'data: [DONE]\n\n';

final _request = ChatRequest(
  systemPrompt: 'Du bist Wendelin.',
  messages: [Message.user('Geheimer Nutzertext')],
  model: 'gpt-oss-120b',
  maxTokens: 50,
);

/// Router, KDS and GitHub in one mock; chat requests are decrypted like the
/// router does and answered with encrypted [_sse].
final class _World {
  _World(this.f) {
    client = MockClient.streaming((request, body) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/chat/completions')) {
        chats++;
        final bytes = await body.toBytes();
        lastWire = bytes;
        lastHeaders = request.headers;
        final ex = f.service.open(request.headers, bytes);
        lastPlain = ex.request;
        final sealed = ex.sealText(_sse);
        return http.StreamedResponse(
          Stream.value(sealed.body),
          200,
          headers: {
            'content-type': 'text/event-stream',
            'Ehbp-Response-Nonce': sealed.nonceHex,
          },
        );
      }
      other.add(request.url.path);
      final r = await f.client.get(request.url, headers: request.headers);
      return http.StreamedResponse(
        Stream.value(r.bodyBytes),
        r.statusCode,
        headers: r.headers,
      );
    });
  }

  final TinfoilFixture f;
  late final http.Client client;
  int chats = 0;
  Uint8List? lastWire;
  Map<String, String>? lastHeaders;
  Map<String, Object?>? lastPlain;
  final List<String> other = [];
}

AttestedProvider _provider(
  _World w, {
  InMemoryAttestationLog? log,
  FixedClock? clock,
}) {
  final gate = TlsPinGate(spkiSha256: (_) => w.f.service.tlsSpkiSha256);
  final c = clock ?? FixedClock(tinfoilNow);
  // The connection to the router is measured with the attested pin.
  final measured = MockClient.streaming((request, body) async {
    gate.observe(Uint8List(1));
    return w.client.send(
      http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = await body.toBytes(),
    );
  });
  return AttestedProvider(
    inner: OpenAiChatAdapter(
      baseUrl: Uri.parse('https://inference.test/v1'),
      credentials: Credentials.apiKey('geheim-key', style: ApiKeyStyle.bearer),
      defaultModel: 'gpt-oss-120b',
      client: measured,
      wireCodec: TinfoilEhbpChannel(crypto: w.f.ehbp, tlsPin: gate),
    ),
    verifier: TinfoilVerifier(
      crypto: FakeAttestationCrypto(),
      snp: w.f.snp,
      sigstore: w.f.sigstore,
      ehbp: w.f.ehbp,
      floors: w.f.floors,
      baseUrl: Uri.parse('https://inference.test/v1'),
      profileId: 'tinfoil',
      client: measured,
      externalClient: w.client,
      settings: HttpSettings(clock: c),
      tlsPin: gate,
    ),
    profileId: 'tinfoil',
    tlsPin: gate,
    requireUpstreamEnforced: false,
    logSink: log,
    settings: HttpSettings(clock: c),
  );
}

void main() {
  test(
    'Antwort: erst Prüfung, dann verschlüsselt, grün ohne Quittung',
    () async {
      final w = _World(TinfoilFixture());
      final log = InMemoryAttestationLog();
      final p = _provider(w, log: log);
      final events = await p.chat(_request).toList();
      expect(events.whereType<ErrorEvent>(), isEmpty, reason: '$events');
      expect(events.last, isA<Done>());
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), 'Hallo');

      // Der Router sah nur Chiffretext, der Klartext kam an der Gegenstelle an.
      expect(
        latin1.decode(w.lastWire!),
        isNot(contains('Geheimer Nutzertext')),
      );
      expect(w.lastPlain.toString(), contains('Geheimer Nutzertext'));
      expect(w.lastHeaders!['Ehbp-Encapsulated-Key'], hasLength(64));

      // Keine Quittung wird angefragt (kein /receipts, kein /signature).
      expect(
        w.other.where((p) => p.contains('receipt') || p.contains('signature')),
        isEmpty,
      );

      final report = (await p.reportFor(_request))!;
      expect(report.status, AttestationStatus.green);
      final receipt = log.entries.lastWhere(
        (e) => e.kind == AttestationLogKind.receipt,
      );
      expect(receipt.status, AttestationStatus.green);
      final none = receipt.stages.single;
      expect(none.stage, AttestationStage.noReceipt);
      expect(none.outcome, StageOutcome.info);
      expect(none.detail, contains('Keine Quittung je Antwort'));
      // Die Sitzungsprüfung steht davor im Prüfprotokoll.
      expect(log.entries.first.kind, AttestationLogKind.session);
      expect(p.toolsEncrypted, isTrue);
    },
  );

  test(
    'zweite Anfrage nutzt die Sitzung, kein neuer Abruf der Quellen',
    () async {
      final w = _World(TinfoilFixture());
      final p = _provider(w);
      await p.chat(_request).toList();
      final before = w.f.requests.length;
      final events = await p.chat(_request).toList();
      expect(events.last, isA<Done>());
      expect(w.f.requests.length, before);
      expect(w.chats, 2);
    },
  );

  test(
    'Prüfung rot: keine Anfrage verlässt das Gerät, kein Klartext-Fallback',
    () async {
      for (final break_ in <void Function(TinfoilFixture)>[
        (f) => f.snp.verdict = const SnpVerdict(
          reportOk: true,
          chainOk: false,
          vcekMatchesReport: true,
          signatureOk: true,
          policyOk: true,
          tlsBound: true,
          hpkeBound: true,
        ),
        (f) => f.sigstore.verdict = SigstoreVerdict(
          dsseOk: true,
          chainOk: true,
          identityOk: true,
          rekorOk: true,
          measurementOk: false,
          integratedTime: f.integratedTime,
        ),
        (f) => f.keyConfig = FakeEhbpService(
          secret: Uint8List(32)..fillRange(0, 32, 5),
        ).keyConfig,
      ]) {
        final f = TinfoilFixture();
        break_(f);
        final w = _World(f);
        final p = _provider(w);
        final events = await p.chat(_request).toList();
        expect(events.single, isA<ErrorEvent>());
        expect(w.chats, 0);
        expect(p.locked, isTrue);
      }
    },
  );

  test(
    'Quelle nicht erreichbar: gelb, nichts gesendet, nach Erholung grün',
    () async {
      final f = TinfoilFixture();
      f.failing['releases/latest'] = 503;
      final w = _World(f);
      final p = _provider(w);
      final first = await p.chat(_request).toList();
      final error =
          (first.single as ErrorEvent).error as AttestationFailedException;
      expect(error.unavailable, isTrue);
      expect(w.chats, 0);
      f.failing.clear();
      final second = await p.chat(_request).toList();
      expect(second.last, isA<Done>());
    },
  );

  test('abgelaufene Sitzung: neue Prüfung vor der nächsten Anfrage', () async {
    final w = _World(TinfoilFixture());
    final clock = FixedClock(tinfoilNow);
    final p = _provider(w, clock: clock);
    await p.chat(_request).toList();
    final before = w.f.requests.length;
    clock.advance(const Duration(minutes: 31));
    await p.chat(_request).toList();
    expect(w.f.requests.length, greaterThan(before));
    expect(w.f.snp.verifies, 2);
  });

  test(
    'Rückschritt des Routers zwischen zwei Sitzungen sperrt den Anbieter',
    () async {
      final f = TinfoilFixture(tag: 'v0.0.159', integratedTime: 1789000500);
      final w = _World(f);
      final clock = FixedClock(tinfoilNow);
      final p = _provider(w, clock: clock);
      await p.chat(_request).toList();
      f
        ..tag = 'v0.0.158'
        ..integratedTime = 1789000000
        ..sigstoreGreen();
      clock.advance(const Duration(minutes: 31));
      final events = await p.chat(_request).toList();
      expect(events.single, isA<ErrorEvent>());
      expect(w.chats, 1);
      expect(p.locked, isTrue);
    },
  );

  test('Kanal ohne gültige Sitzung verschlüsselt nichts', () async {
    final channel = TinfoilEhbpChannel(crypto: EhbpReferenceCrypto());
    channel.bind(() => null, FixedClock(tinfoilNow));
    await expectLater(
      channel.begin(model: 'm'),
      throwsA(isA<AttestationFailedException>()),
    );
    expect(
      () => channel.bind(() => null, FixedClock(tinfoilNow)),
      throwsStateError,
    );
  });

  test('Protokolleinträge enthalten weder Klartext noch Schlüssel', () async {
    final f = TinfoilFixture();
    final w = _World(f);
    final log = InMemoryAttestationLog();
    await _provider(w, log: log).chat(_request).toList();
    final text = jsonEncode([for (final e in log.entries) e.toJson()]);
    expect(text, isNot(contains('Geheimer Nutzertext')));
    expect(text, isNot(contains('geheim-key')));
    expect(text, isNot(contains(AttestCodec.hex(f.service.publicKey))));
  });
}
