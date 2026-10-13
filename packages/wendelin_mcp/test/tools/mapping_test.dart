import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

void main() {
  group('Slug (Tabelle)', () {
    for (final (name, taken, expected) in [
      ('Homeserver', <String>{}, 'homeserver'),
      ('Home Assistant', <String>{}, 'homeassistant'),
      ('Büro-Rechner Ö', <String>{}, 'buerorechneroe'),
      ('Straße 42', <String>{}, 'strasse42'),
      ('Café façade', <String>{}, 'cafefacade'),
      ('🚀 !!!', <String>{}, 'server'),
      ('', <String>{}, 'server'),
      ('Ein sehr langer Servername', <String>{}, 'einsehrlangerser'),
      ('Home', {'home'}, 'home2'),
      ('Home', {'home', 'home2'}, 'home3'),
      ('Ein sehr langer Servername', {'einsehrlangerser'}, 'einsehrlangerse2'),
      (
        'Ein sehr langer Servername',
        {for (var i = 2; i <= 9; i++) 'einsehrlangerse$i', 'einsehrlangerser'},
        'einsehrlangers10',
      ),
    ]) {
      test('„$name“ (belegt: $taken) → $expected', () {
        final slug = McpNaming.slugFor(name, taken: taken);
        expect(slug, expected);
        expect(slug.length, lessThanOrEqualTo(McpNaming.maxSlug));
        expect(RegExp(r'^[a-z0-9]+$').hasMatch(slug), isTrue);
      });
    }
  });

  group('Tool-Namen (Tabelle)', () {
    final long16 = 'a' * 16;
    for (final (slug, tool, expected) in [
      ('home', 'get_weather', 'mcp_home__get_weather'),
      ('home', 'Get-Weather_2', 'mcp_home__Get-Weather_2'),
      ('home', 'docker.restart', null), // ungültiges Zeichen → Hash
      ('home', 'mit leerzeichen', null),
      ('home', 'ümlaut', null),
      (long16, 'x' * 42, 'mcp_${long16}__${'x' * 42}'), // genau 64
      (long16, 'x' * 43, null), // 65 → gekürzt mit Hash
    ]) {
      test('$slug / $tool', () {
        final name = McpNaming.toolNames(slug, [tool])[tool]!;
        expect(Tool.isValidToolName(name), isTrue, reason: name);
        expect(name.length, lessThanOrEqualTo(64));
        expect(name, startsWith('mcp_${slug}__'));
        if (expected != null) {
          expect(name, expected);
        } else {
          expect(name, matches(RegExp(r'_[0-9a-f]{6}$')));
        }
      });
    }

    test('Kürzung behält Anfang und hängt Hash an', () {
      final tool = 'list_${'very_long_' * 10}things';
      final name = McpNaming.toolNames('home', [tool])[tool]!;
      expect(name.length, 64);
      expect(name, startsWith('mcp_home__list_very_long_'));
    });

    test('Kollisionen: a.b und a_b und a b bekommen verschiedene Namen', () {
      final names = McpNaming.toolNames('s', ['a_b', 'a.b', 'a b', 'a-b']);
      expect(names['a_b'], 'mcp_s__a_b');
      expect(names['a-b'], 'mcp_s__a-b');
      expect(names.values.toSet(), hasLength(4));
      expect(names['a.b'], isNot(names['a b']));
    });

    test('lange Namen mit gleichem Anfang kollidieren nicht', () {
      final tools = [for (var i = 0; i < 20; i++) '${'p' * 60}$i'];
      final names = McpNaming.toolNames('srv', tools);
      expect(names.values.toSet(), hasLength(20));
      expect(names.values.every((n) => n.length <= 64), isTrue);
    });

    test(
      'Zuordnung ist stabil (unabhängig von Reihenfolge und anderen Tools)',
      () {
        final a = McpNaming.toolNames('s', ['docker.restart', 'z', 'y.y']);
        final b = McpNaming.toolNames('s', ['y.y', 'docker.restart']);
        expect(a['docker.restart'], b['docker.restart']);
        expect(a['y.y'], b['y.y']);
      },
    );

    test('Hash-Name kollidiert mit unverändertem Namen → längerer Hash', () {
      final hashed = McpNaming.toolNames('s', ['a.b'])['a.b']!;
      final plain = hashed.substring('mcp_s__'.length);
      final names = McpNaming.toolNames('s', ['a.b', plain]);
      expect(names[plain], hashed);
      expect(names['a.b'], matches(RegExp(r'_[0-9a-f]{8}$')));
    });

    test('Duplikate in der Eingabe zählen einmal', () {
      expect(McpNaming.toolNames('s', ['x', 'x']), {'x': 'mcp_s__x'});
      expect(McpNaming.prefix('s'), 'mcp_s__');
    });
  });

  group('Risiko (Tabelle)', () {
    const r = RiskLevel.read;
    const w = RiskLevel.write;
    const e = RiskLevel.external;
    // Alle Hinweis-Kombinationen (null/true/false) × autoRun × confirmAll.
    // Spalten: readOnly, destructive, Basis, effektiv ohne autoRun,
    // effektiv mit autoRun (jeweils ohne confirmAll).
    for (final (readOnly, destructive, base, plain, auto) in [
      (null, null, e, e, e), // fehlender destructiveHint zählt als true
      (null, true, e, e, e),
      (null, false, w, e, w), // write ohne Undo → bestätigen, außer autoRun
      (true, null, r, r, r),
      (true, true, r, r, r), // destructiveHint gilt nur ohne readOnlyHint
      (true, false, r, r, r),
      (false, null, e, e, e),
      (false, true, e, e, e),
      (false, false, w, e, w),
    ]) {
      final a = McpToolAnnotations(
        readOnlyHint: readOnly,
        destructiveHint: destructive,
      );
      for (final autoRun in [false, true]) {
        for (final confirmAll in [false, true]) {
          final expected = confirmAll ? e : (autoRun ? auto : plain);
          test('readOnly=$readOnly destructive=$destructive autoRun=$autoRun '
              'confirmAll=$confirmAll → ${expected.name}', () {
            expect(
              mcpBaseRisk(a, confirmAll: confirmAll),
              confirmAll ? e : base,
            );
            expect(
              mcpRisk(a, confirmAll: confirmAll, autoRun: autoRun),
              expected,
            );
          });
        }
      }
    }

    const ro = McpToolAnnotations(readOnlyHint: true);
    const writeTool = McpToolAnnotations(destructiveHint: false);
    for (final (label, annotations, autoRun, override, expected) in [
      ('Override verschärft read→write', ro, false, w, w),
      ('Override verschärft read→external', ro, false, e, e),
      ('Override verschärft autoRun-write→external', writeTool, true, e, e),
      ('Override lockert nicht external→read', writeTool, false, r, e),
      ('Override lockert nicht autoRun-write→read', writeTool, true, r, w),
      ('Override gleich', writeTool, true, w, w),
      ('autoRun wirkt nicht auf read', ro, true, null, r),
    ]) {
      test(label, () {
        expect(
          mcpRisk(annotations, autoRun: autoRun, override: override),
          expected,
        );
      });
    }
    test('Override lockert confirmAll nicht, autoRun auch nicht', () {
      expect(
        mcpRisk(writeTool, confirmAll: true, autoRun: true, override: r),
        e,
      );
    });
  });

  group('Netzziele (Tabelle)', () {
    for (final (url, allowed) in [
      ('https://mcp.example.com/mcp', true),
      ('https://1.2.3.4/mcp', true),
      ('http://mcp.example.com/mcp', false),
      ('http://8.8.8.8/mcp', false),
      ('http://192.168.1.10:8080/mcp', true),
      ('http://10.0.2.2:3000/mcp', true),
      ('http://172.16.0.5/mcp', true),
      ('http://172.32.0.5/mcp', false),
      ('http://100.64.0.1/mcp', true),
      ('http://100.101.102.103/mcp', true),
      ('http://100.128.0.1/mcp', false),
      ('http://homeserver.tail1234.ts.net/mcp', true),
      ('http://nas.local/mcp', true),
      ('http://nas.home.arpa/mcp', true),
      ('http://localhost:8080/mcp', true),
      ('http://127.0.0.1/mcp', true),
      ('http://[::1]/mcp', true),
      ('http://[fd7a:115c:a1e0::1]/mcp', true),
      ('http://[fe80::1]/mcp', true),
      ('http://[2001:db8::1]/mcp', false),
      ('http://ts.net.evil.com/mcp', false),
      ('http://nas/mcp', false),
      ('https://user:pass@mcp.example.com/mcp', false),
      ('https://token@mcp.example.com/mcp', false),
      ('http://user@192.168.1.10/mcp', false),
      ('ftp://192.168.1.10/mcp', false),
      ('ws://192.168.1.10/mcp', false),
      ('https:///mcp', false),
    ]) {
      test('$url → ${allowed ? 'erlaubt' : 'abgelehnt'}', () {
        final uri = Uri.parse(url);
        if (allowed) {
          expect(() => checkServerUrl(uri), returnsNormally);
        } else {
          expect(
            () => checkServerUrl(uri),
            throwsA(
              isA<McpException>().having(
                (e) => e.kind,
                'kind',
                McpErrorKind.rejected,
              ),
            ),
          );
        }
      });
    }

    for (final (url, allowed) in [
      ('https://auth.example.com/token', true),
      ('http://auth.example.com/token', false),
      ('http://192.168.1.10/token', false),
      ('http://localhost:9000/token', true),
      ('http://127.0.0.1:9000/token', true),
      ('https://u:p@auth.example.com/token', false),
      ('custom://auth', false),
    ]) {
      test('OAuth $url → ${allowed ? 'erlaubt' : 'abgelehnt'}', () {
        final uri = Uri.parse(url);
        if (allowed) {
          expect(() => checkOAuthUrl(uri), returnsNormally);
        } else {
          expect(() => checkOAuthUrl(uri), throwsA(isA<McpException>()));
        }
      });
    }

    for (final (from, to, ok) in [
      ('https://a.example/mcp', 'https://a.example/v2/mcp', true),
      ('https://a.example/mcp', 'https://A.EXAMPLE/other', true),
      ('https://a.example/mcp', 'https://b.example/mcp', false),
      ('https://a.example/mcp', 'http://a.example/mcp', false),
      ('https://a.example/mcp', 'https://a.example:8443/mcp', false),
      ('http://192.168.1.2/mcp', 'http://192.168.1.3/mcp', false),
    ]) {
      test('Weiterleitung $from → $to ${ok ? 'erlaubt' : 'abgelehnt'}', () {
        void call() => checkRedirect(Uri.parse(from), Uri.parse(to));
        ok
            ? expect(call, returnsNormally)
            : expect(call, throwsA(isA<McpException>()));
      });
    }

    test('Hilfsfunktionen', () {
      expect(isLoopbackHost('LOCALHOST.'), isTrue);
      expect(isLoopbackHost('app.localhost'), isTrue);
      expect(isLoopbackHost('[::1]'), isTrue);
      expect(isLoopbackHost('example.com'), isFalse);
      expect(isHomeNetworkHost('192.168.0.1'), isTrue);
      expect(isHomeNetworkHost('example.com'), isFalse);
    });
  });

  group('Schema', () {
    test('type object wird ergänzt, Schema sonst unverändert', () {
      final s = McpSchema.from({
        'properties': {
          'q': {'type': 'string', 'description': 'Suche', 'minLength': 1},
        },
        'required': ['q'],
      });
      expect(s.schema['type'], 'object');
      expect(s.schema['required'], ['q']);
      expect(s.unsupported, isEmpty);
      expect(McpSchema.from({'type': 'object'}).schema, {'type': 'object'});
    });

    test('nicht unterstützte Teile werden mit Pfad gemeldet', () {
      final s = McpSchema.from({
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'properties': {
          'container': {'type': 'string', 'pattern': '^[a-z]+\$'},
          'when': {
            'anyOf': [
              {'type': 'string'},
              {'type': 'null'},
            ],
          },
          'mail': {'type': 'string', 'format': 'email'},
          'at': {'type': 'string', 'format': 'date-time'},
          'tags': {
            'type': 'array',
            'items': {'type': 'string', 'const': 'x'},
            'minItems': 1,
          },
          'pair': {
            'type': 'array',
            'items': [
              {'type': 'string'},
            ],
          },
          'map': {
            'type': 'object',
            'additionalProperties': {'type': 'integer', 'multipleOf': 2},
          },
        },
        r'$defs': {'x': <String, Object?>{}},
      });
      expect(
        s.unsupported,
        unorderedEquals([
          'container: pattern',
          'when: anyOf',
          'mail: format email',
          'tags.items: const',
          'tags: minItems',
          'pair.items: Tupel',
          'map.additionalProperties: multipleOf',
          r'(Wurzel): $defs',
        ]),
      );
      // Das Schema geht unverändert ans Modell (nichts still verworfen).
      expect((s.schema['properties']! as Map<String, Object?>)['container'], {
        'type': 'string',
        'pattern': '^[a-z]+\$',
      });
      expect(McpSchema.from({'type': 'object', 'format': 'uri'}).unsupported, [
        '(Wurzel): format uri',
      ]);
    });
  });

  group('Konfiguration', () {
    McpServerConfig sample(McpAuth auth) => McpServerConfig(
      id: 'srv-1',
      name: 'Homeserver',
      slug: 'homeserver',
      url: Uri.parse('http://100.100.1.2:8080/mcp'),
      transport: McpTransportKind.streamable,
      auth: auth,
      sensitive: true,
      confirmAll: true,
      toolOverrides: const {
        'shell': McpToolOverride(risk: RiskLevel.external),
        'note': McpToolOverride(autoRun: true),
        'debug': McpToolOverride(enabled: false),
      },
    );

    for (final auth in <McpAuth>[
      const McpNoAuth(),
      const McpBearerAuth('mcp.srv-1.bearer'),
      McpHeadersAuth({'X-Api-Key': 'mcp.srv-1.key'}),
      McpOAuth(
        tokenRef: 'mcp.srv-1.tokens',
        clientRef: 'mcp.srv-1.client',
        clientId: 'wendelin',
        scopes: ['mcp:tools'],
      ),
      McpOAuth(tokenRef: 't', clientRef: 'c'),
    ]) {
      test('JSON-Rundreise mit $auth', () {
        final config = sample(auth);
        final back = McpServerConfig.fromJson(config.toJson());
        expect(back, config);
        expect(back.hashCode, config.hashCode);
        expect(back.auth.secretRefs, auth.secretRefs);
        expect(back.auth.hashCode, auth.hashCode);
        expect(config.integrationId, 'mcp_homeserver');
        expect(config.toString(), contains('Homeserver'));
      });
    }

    test('Standardwerte und copyWith', () {
      final c = McpServerConfig.fromJson({
        'id': 'x',
        'name': 'X',
        'slug': 'x',
        'url': 'https://x.example/mcp',
        'auth': {'kind': 'none'},
      });
      expect(c.transport, McpTransportKind.auto);
      expect(c.enabled, isTrue);
      expect(c.sensitive, isFalse);
      expect(c.toolOverrides, isEmpty);
      expect(c.toJson().containsKey('toolOverrides'), isFalse);
      final d = c.copyWith(
        name: 'Y',
        enabled: false,
        url: Uri.parse('https://y.example/mcp'),
        transport: McpTransportKind.sse,
        auth: const McpBearerAuth('r'),
        sensitive: true,
        confirmAll: true,
        toolOverrides: const {'a': McpToolOverride(enabled: false)},
      );
      expect(d.slug, 'x');
      expect(d.name, 'Y');
      expect(d, isNot(c));
      expect(c.copyWith(), c);
      expect(const McpToolOverride().toJson(), isEmpty);
      expect(
        const McpToolOverride(risk: RiskLevel.read).toString(),
        contains('read'),
      );
      expect(
        const McpToolOverride(autoRun: true).toString(),
        contains('autoRun'),
      );
      expect(const McpToolOverride(autoRun: true).toJson(), {'autoRun': true});
      expect(
        const McpToolOverride(autoRun: true),
        isNot(const McpToolOverride()),
      );
    });

    for (final (label, json) in [
      (
        'ohne id',
        {
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'auth': {'kind': 'none'},
        },
      ),
      (
        'kaputte url',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'http://[::1',
          'auth': {'kind': 'none'},
        },
      ),
      (
        'unbekannter Transport',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'transport': 'ws',
          'auth': {'kind': 'none'},
        },
      ),
      (
        'unbekannte Auth',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'auth': {'kind': 'basic'},
        },
      ),
      (
        'Header-Referenz kein Text',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'auth': {
            'kind': 'headers',
            'secretRefs': {'a': 1},
          },
        },
      ),
      (
        'Scope kein Text',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'auth': {
            'kind': 'oauth',
            'tokenRef': 't',
            'clientRef': 'c',
            'scopes': [1],
          },
        },
      ),
      (
        'enabled falsch',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'enabled': 'ja',
          'auth': {'kind': 'none'},
        },
      ),
      (
        'Override kein Objekt',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'auth': {'kind': 'none'},
          'toolOverrides': {'a': 1},
        },
      ),
      (
        'Override-Risiko unbekannt',
        {
          'id': 'x',
          'name': 'X',
          'slug': 'x',
          'url': 'https://x',
          'auth': {'kind': 'none'},
          'toolOverrides': {
            'a': {'risk': 'egal'},
          },
        },
      ),
    ]) {
      test('Formatfehler: $label', () {
        expect(() => McpServerConfig.fromJson(json), throwsFormatException);
      });
    }
  });

  test('McpException: retryable und Gleichheit', () {
    const e = McpException(McpErrorKind.server, 'x', statusCode: 503);
    expect(e.retryable, isTrue);
    expect(
      const McpException(McpErrorKind.server, 'x', statusCode: 400).retryable,
      isFalse,
    );
    expect(const McpException(McpErrorKind.server, 'x').retryable, isFalse);
    expect(const McpException(McpErrorKind.timeout, 'x').retryable, isTrue);
    expect(
      const McpException(McpErrorKind.authRequired, 'x').retryable,
      isFalse,
    );
    expect(e, const McpException(McpErrorKind.server, 'x', statusCode: 503));
    expect(
      e.hashCode,
      const McpException(McpErrorKind.server, 'x', statusCode: 503).hashCode,
    );
    expect(e.withMessage('y').message, 'y');
    expect(e.toString(), 'McpException(server): x');
  });
}
