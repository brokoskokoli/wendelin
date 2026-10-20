import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('evals_cli'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(int, String, String)> run(
    List<String> args, {
    Map<String, String> env = const {},
    http.Client? client,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      args,
      env: env,
      out: out,
      err: err,
      client: client,
    );
    return (code, '$out', '$err');
  }

  test('Probelauf mit Fake-Provider erzeugt Report', () async {
    final path = '${tmp.path}/sub/fake.json';
    final (code, out, err) = await run([
      '--profile',
      'profiles/fake-demo.json',
      '--out',
      path,
    ]);
    expect(code, 0, reason: err);
    expect(out, contains('Profil fake-demo (fake), Modell fake-model'));
    expect(out, contains('gesamt'));
    expect(out, contains('Report: $path'));
    final report =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final summary = report['summary']! as Map<String, Object?>;
    // Das Demo-Skript beantwortet 15 von 150 Fällen richtig (Rest: weiß ich nicht).
    expect(summary['total'], 150);
    expect(summary['passed'], 15);
    expect(summary['skipped'], 2);
    expect(summary['gaveUp'], 1);
    expect(summary['escalated'], 0);
    expect(summary['costMicros'], greaterThan(0));
    expect(summary['unpricedCases'], 0);
    final byLang = report['byLanguage']! as Map<String, Object?>;
    expect(byLang.keys, ['de', 'en', 'fr']);
    final cases = (report['cases']! as List).cast<Map<String, Object?>>();
    Map<String, Object?> byId(String id) =>
        cases.firstWhere((c) => c['id'] == id);
    expect(byId('de-cal-tauchen')['status'], 'passed');
    expect(byId('de-cal-zahnarzt-freitag')['status'], 'failed');
    expect(byId('de-cal-loeschen')['confirmations'], 1);
    expect(byId('de-mem-tochter')['gaveUp'], isTrue);
    expect(byId('de-smalltalk-danke')['reasons'], [
      'Kein Tool erwartet, aufgerufen: memory__save',
    ]);
    expect(byId('de-lists-add')['status'], 'skipped');
    expect((report['meta']! as Map)['now'], '2026-11-18T09:00');
  });

  test('Filter, Limit, Modell, eigenes Fall-Verzeichnis und heute', () async {
    final (code, out, _) = await run([
      '-p',
      'profiles/fake-demo.json',
      '--cases',
      'calendar,smalltalk',
      '--limit',
      '3',
      '--model',
      'fake-strong',
      '--cases-dir',
      'cases',
      '--now',
      '2026-10-20T08:00',
    ]);
    expect(code, 0);
    expect(
      out,
      contains('Modell fake-strong, 3 Fälle, heute = 2026-10-20T08:00'),
    );
  });

  test('--integrations reduziert den Tool-Katalog', () async {
    final all = await run([
      '-p',
      'profiles/fake-demo.json',
      '-c',
      'de-cal-tauchen',
    ]);
    final reduced = await run([
      '-p',
      'profiles/fake-demo.json',
      '-c',
      'de-cal-tauchen',
      '--integrations',
      'alarms,memory',
    ]);
    expect(all.$2, contains('1/1'));
    expect(reduced.$2, isNot(contains('1/1')));
  });

  test('pending-Fälle mit --include-pending', () async {
    final (code, out, _) = await run([
      '-p',
      'profiles/fake-demo.json',
      '-c',
      'lists',
      '--include-pending',
    ]);
    expect(code, 0);
    expect(out, contains('de-lists-add: failed'));
  });

  test('Hilfe und Bedienfehler', () async {
    expect((await run(['--help'])).$2, contains('--profile'));
    expect((await run([])).$1, 64);
    expect((await run(['--bogus'])).$1, 64);
    expect((await run(['-p', 'x.json', '--limit', '0'])).$1, 64);
    expect((await run(['-p', 'x.json', '--limit', 'viele'])).$1, 64);
  });

  test('Einrichtungsfehler', () async {
    final missing = await run(['-p', '${tmp.path}/fehlt.json']);
    expect(missing.$1, 1);
    expect(missing.$3, contains('Fehler'));

    final none = await run([
      '-p',
      'profiles/fake-demo.json',
      '-c',
      'gibtsnicht',
    ]);
    expect(none.$1, 1);
    expect(none.$3, contains('Keine Fälle'));

    final badNow = await run([
      '-p',
      'profiles/fake-demo.json',
      '--now',
      'gestern',
    ]);
    expect(badNow.$1, 1);

    final noScript = File('${tmp.path}/fake.json')
      ..writeAsStringSync(
        jsonEncode({
          'id': 'f',
          'name': 'F',
          'type': 'fake',
          'defaultModel': 'm',
          'privacy': 'local',
          'authMethod': {'kind': 'none'},
        }),
      );
    final r = await run(['-p', noScript.path]);
    expect(r.$1, 1);
    expect(r.$3, contains('script'));

    final noUrl = File('${tmp.path}/nourl.json')
      ..writeAsStringSync(
        jsonEncode({
          'id': 'o',
          'name': 'O',
          'type': 'openaiCompatible',
          'defaultModel': 'm',
          'privacy': 'standard',
          'authMethod': {'kind': 'none'},
        }),
      );
    final r2 = await run(['-p', noUrl.path]);
    expect(r2.$1, 1);
    expect(r2.$3, contains('Base-URL'));
  });

  test('unbekannte Zeitzone ist ein Einrichtungsfehler (Review #4)', () async {
    final (code, _, err) = await run([
      '-p',
      'profiles/fake-demo.json',
      '--time-zone',
      'Mars/Olympus',
    ]);
    expect(code, 1);
    expect(err, contains('Unbekannte Zeitzone „Mars/Olympus“'));
  });

  test('Strg+C: Teilreport wird geschrieben (Review #5)', () async {
    final path = '${tmp.path}/teil.json';
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      ['-p', 'profiles/fake-demo.json', '-c', 'de', '--out', path],
      env: const {},
      out: out,
      err: err,
      interrupt: Stream.value(null),
    );
    expect(code, 130);
    expect('$err', contains('Abbruch angefordert'));
    final report =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    expect((report['meta']! as Map)['interrupted'], isTrue);
    final cases = (report['cases']! as List).cast<Map<String, Object?>>();
    expect(cases.first['status'], isNot('skipped'));
    expect(cases.last['reasons'], ['abgebrochen']);
    expect((report['summary']! as Map)['total'], lessThan(cases.length));
  });

  test('Warnung bei Modell ohne Katalogpreis (Review #5)', () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    final (_, _, err) = await run(
      ['-p', 'profiles/claude-haiku.json', '-m', 'claude-unbekannt', '-n', '1'],
      env: {'ANTHROPIC_API_KEY': 'test-key-123'},
      client: client,
    );
    expect(err, contains('Warnung: kein Preis für Modell claude-unbekannt'));
    final fake = await run(['-p', 'profiles/fake-demo.json', '-n', '1']);
    expect(fake.$3, isNot(contains('Warnung')));
  });

  test('echter Provider: Key fehlt in der Umgebung', () async {
    final (code, _, err) = await run(['-p', 'profiles/claude-haiku.json']);
    expect(code, 1);
    expect(err, contains('ANTHROPIC_API_KEY fehlt'));
  });

  test('echter Provider: Key aus der Umgebung, HTTP über den Client', () async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['x-api-key']);
      return http.Response(
        '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}',
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    final (code, out, _) = await run(
      [
        '-p',
        'profiles/claude-haiku.json',
        '--limit',
        '1',
        '-c',
        'de-cal-tauchen',
      ],
      env: {'ANTHROPIC_API_KEY': 'test-key-123'},
      client: client,
    );
    expect(code, 0);
    expect(seen, isNotEmpty);
    expect(seen.first, 'test-key-123');
    expect(out, contains('de-cal-tauchen: error'));
    expect(out, isNot(contains('test-key-123')));
  });

  test(
    'TEE-Profil läuft ohne Prüf-Verdrahtung, mit aci_verified (WP54b)',
    () async {
      final bodies = <String>[];
      final auth = <String?>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        auth.add(req.headers['authorization']);
        return http.Response('{}', 401);
      });
      final (code, out, err) = await run(
        ['-p', 'profiles/phala-tee-small.json', '-c', 'de-cal-tauchen'],
        env: {'PHALA_API_KEY': 'test-key-123'},
        client: client,
      );
      expect(code, 0, reason: err);
      expect(out, contains('de-cal-tauchen: error'));
      expect(auth.first, 'Bearer test-key-123');
      expect(bodies.first, contains('"aci_verified":true'));
      expect(out, isNot(contains('test-key-123')));
    },
  );

  test(
    'Provider fällt nach einem Aufruf aus: Ledger bucht Kosten und budgetGroup',
    () async {
      var calls = 0;
      final client = MockClient.streaming((req, body) async {
        await body.drain<void>();
        calls++;
        if (calls > 1) throw StateError('Test: unerwarteter Fehler');
        const chunks =
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1",'
            '"type":"function","function":{"name":"calendar__list_events",'
            '"arguments":"{}"}}]},"finish_reason":"tool_calls","index":0}],'
            '"usage":{"prompt_tokens":1000,"completion_tokens":100,'
            '"total_tokens":1100}}\n\ndata: [DONE]\n\n';
        return http.StreamedResponse(
          Stream.value(utf8.encode(chunks)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final ledger = '${tmp.path}/l.json';
      final (code, out, err) = await run(
        [
          '-p',
          'profiles/openai-mini.json',
          '-c',
          'de-cal-tauchen',
          '--ledger',
          ledger,
          '--max-cost',
          '1',
        ],
        env: {'OPENAI_API_KEY': 'test-key-123'},
        client: client,
      );
      expect(code, 0, reason: err);
      expect(out, contains('de-cal-tauchen: error'));
      final entry = readLedger(File(ledger)).single;
      expect(entry.budgetGroup, 'openai');
      expect(entry.costUsd, greaterThan(0), reason: '$calls Aufrufe');
    },
  );

  group('Anfrage-Felder je Modell (modelOptions, WP112)', () {
    /// First request body of a run of `-c de-cal-tauchen` with [profile].
    Future<Map<String, Object?>> requestOf(
      String profile, {
      String? model,
      String key = 'PHALA_API_KEY',
    }) async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('{}', 401);
      });
      final (code, _, err) = await run(
        [
          '-p',
          'profiles/$profile.json',
          '-c',
          'de-cal-tauchen',
          if (model != null) ...['-m', model],
        ],
        env: {key: 'test-key-123'},
        client: client,
      );
      expect(code, 0, reason: err);
      expect(bodies, isNotEmpty);
      return jsonDecode(bodies.first) as Map<String, Object?>;
    }

    Future<Map<String, Object?>> tinfoil(String? model) =>
        requestOf('tinfoil-tee', model: model, key: 'TINFOIL_API_KEY');

    test(
      'Tinfoil gpt-oss-120b: reasoning_effort low, kein Template-Feld',
      () async {
        final body = await tinfoil(null);
        expect(body['model'], 'gpt-oss-120b');
        expect(body['reasoning_effort'], 'low');
        expect(body, isNot(contains('chat_template_kwargs')));
      },
    );

    test('Tinfoil gemma4-31b: enable_thinking false, sonst nichts', () async {
      final body = await tinfoil('gemma4-31b');
      expect(body['model'], 'gemma4-31b');
      expect(body['chat_template_kwargs'], {'enable_thinking': false});
      expect(body, isNot(contains('reasoning_effort')));
    });

    test('Tinfoil deepseek-v4-1-flash: thinking false', () async {
      final body = await tinfoil('deepseek-v4-1-flash');
      expect(body['chat_template_kwargs'], {'thinking': false});
      expect(body, isNot(contains('reasoning_effort')));
    });

    test('Phala gpt-oss-120b: reasoning low, aci_verified bleibt', () async {
      final body = await requestOf(
        'phala-tee-small',
        model: 'openai/gpt-oss-120b',
      );
      expect(body['reasoning_effort'], 'low');
      expect((body['provider'] as Map)['aci_verified'], isTrue);
    });

    test('Phala gemma-4-31b-it: reasoning.enabled false', () async {
      final body = await requestOf(
        'phala-tee-small',
        model: 'google/gemma-4-31b-it',
      );
      expect(body['reasoning'], {'enabled': false});
      expect(body, isNot(contains('reasoning_effort')));
      expect((body['provider'] as Map)['aci_verified'], isTrue);
    });

    test('Phala deepseek-v4-flash: thinking false', () async {
      final body = await requestOf(
        'phala-tee-small',
        model: 'deepseek/deepseek-v4-flash-0731',
      );
      expect(body['chat_template_kwargs'], {'thinking': false});
      expect(body, isNot(contains('reasoning_effort')));
    });

    test('OpenAI gpt-5-mini: reasoning_effort minimal', () async {
      final body = await requestOf('openai-mini', key: 'OPENAI_API_KEY');
      expect(body['model'], 'gpt-5-mini');
      expect(body['reasoning_effort'], 'minimal');
    });

    test('Claude Sonnet: thinking disabled im Request', () async {
      final body = await requestOf('claude-sonnet', key: 'ANTHROPIC_API_KEY');
      expect(body['thinking'], {'type': 'disabled'});
    });

    test('Phala anderes Modell: kein reasoning_effort', () async {
      final body = await requestOf('phala-tee-small');
      expect(body, isNot(contains('reasoning_effort')));
    });
  });
}
