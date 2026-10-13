import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support.dart';

Map<String, Object?> roundTrip(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('JSON-Rundreise', () {
    final full = def(
      name: 'ha_light',
      method: HttpMethod.post,
      url: 'http://ha.local:8123/api/services/light/{id}?q={q}',
      headers: {'X-Room': '{room}'},
      body: {
        'entity_id': '{id}',
        'brightness': '{level}',
        'list': [1, '{q}'],
      },
      auth: const ApiKeyAuth('ha-token'),
      risk: RiskLevel.external,
      sensitive: true,
      homeNetwork: true,
      enabled: false,
      timeout: const Duration(seconds: 30),
      responsePath: 'data.0',
    );

    test('vollständige Definition', () {
      final json = roundTrip(full.toJson());
      expect(json['schemaVersion'], httpToolSchemaVersion);
      final back = HttpToolDefinition.fromJson(json);
      expect(back, full);
      expect(back.hashCode, full.hashCode);
      expect(back.toJson(), full.toJson());
      expect(back.timeout, const Duration(seconds: 30));
      expect(back.bodyFormat, HttpBodyFormat.json);
    });

    test('minimale Definition mit Standardwerten', () {
      final json = roundTrip({
        'schemaVersion': 1,
        'id': 'x',
        'name': 'ping',
        'description': 'Ping',
        'method': 'get',
        'url': 'https://api.example.org/ping',
        'inputSchema': {'type': 'object'},
      });
      final d = HttpToolDefinition.fromJson(json);
      expect(d.method, HttpMethod.get);
      expect(d.auth, const NoAuth());
      expect(d.risk, RiskLevel.read);
      expect(d.enabled, isTrue);
      expect(d.sensitive, isFalse);
      expect(d.homeNetwork, isFalse);
      expect(d.timeout, httpToolDefaultTimeout);
      expect(d.toolName, 'http__ping');
      expect(d.toString(), 'HttpToolDefinition(http__ping, GET)');
    });

    test('Formular und CustomHeaders', () {
      final d = def(
        method: HttpMethod.patch,
        url: 'https://api.example.org/f',
        body: {'a': '{q}'},
        bodyFormat: HttpBodyFormat.form,
        auth: CustomHeadersAuth({'X-Token': 'ref-1'}),
      );
      expect(HttpToolDefinition.fromJson(roundTrip(d.toJson())), d);
    });

    test('Export/Import einer Liste', () {
      final list = [full, def(name: 'zweites')];
      final exported = roundTrip(exportHttpTools(list));
      expect(exported['schemaVersion'], httpToolSchemaVersion);
      expect(importHttpTools(exported), list);
    });

    test('copyWith', () {
      final d = def();
      final c = d.copyWith(
        name: 'neu',
        description: 'd',
        method: HttpMethod.delete,
        urlTemplate: 'https://api.example.org/x/{id}',
        inputSchema: d.inputSchema,
        headers: const {'X-A': 'b'},
        auth: const NoAuth(),
        risk: RiskLevel.write,
        sensitive: true,
        homeNetwork: true,
        enabled: false,
        timeout: const Duration(seconds: 5),
      );
      expect(c.id, d.id);
      expect(c.name, 'neu');
      expect(c.method, HttpMethod.delete);
      expect(c.effectiveRisk, RiskLevel.external);
      expect(c.autoRun, isFalse);
      expect(d.copyWith(autoRun: true).autoRun, isTrue);
      expect(d.copyWith(), d);
      expect(c == d, isFalse);
    });
  });

  group('Import lehnt ungültige Definitionen lesbar ab', () {
    Map<String, Object?> base() => roundTrip(def().toJson());
    final cases = <String, (void Function(Map<String, Object?>), String)>{
      'Version fehlt': ((j) => j.remove('schemaVersion'), 'schemaVersion'),
      'Version zu neu': ((j) => j['schemaVersion'] = 99, 'Version 99'),
      'Name fehlt': ((j) => j.remove('name'), '„name“ fehlt'),
      'Name mit Punkt': ((j) => j['name'] = 'a.b', 'Name nur aus'),
      'Name mit Leerzeichen': ((j) => j['name'] = 'a b', 'Name nur aus'),
      'Name zu lang': ((j) => j['name'] = 'a' * 59, '1–58'),
      'Beschreibung leer': ((j) => j['description'] = ' ', 'Beschreibung'),
      'Beschreibung zu lang': ((j) => j['description'] = 'x' * 2001, 'zu lang'),
      'id leer': ((j) => j['id'] = '', '„id“'),
      'Methode unbekannt': ((j) => j['method'] = 'TRACE', 'TRACE'),
      'Methode falscher Typ': ((j) => j['method'] = 1, '„method“'),
      'Platzhalter im Host': (
        (j) => j['url'] = 'https://{id}.example.org/',
        'nicht in Schema, Host oder Port',
      ),
      'http öffentlich': (
        (j) => j['url'] = 'http://api.example.org/{id}',
        'nur für Heimnetz',
      ),
      'unbekannter Platzhalter': (
        (j) => j['url'] = 'https://api.example.org/{nope}',
        '„{nope}“ ist kein Argument',
      ),
      'Schema nicht object': (
        (j) => j['inputSchema'] = {'type': 'string'},
        'type: object',
      ),
      'Schema-properties kein Objekt': (
        (j) => j['inputSchema'] = {'type': 'object', 'properties': 1},
        'properties',
      ),
      'required unbekannt': (
        (j) => j['inputSchema'] = {
          'type': 'object',
          'properties': <String, Object?>{},
          'required': ['x'],
        },
        'required',
      ),
      'Header nicht Text': ((j) => j['headers'] = {'X-A': 1}, 'X-A'),
      'Header-Name ungültig': (
        (j) => j['headers'] = {'X A': 'b'},
        'ungültiger Header-Name',
      ),
      'Header Host': ((j) => j['headers'] = {'Host': 'evil'}, 'setzt die App'),
      'Header Authorization im Klartext': (
        (j) => j['headers'] = {'Authorization': 'Bearer abc'},
        'sieht geheim aus',
      ),
      'Header X-Api-Key im Klartext': (
        (j) => j['headers'] = {'X-Api-Key': 'abc'},
        'sieht geheim aus',
      ),
      'Header doppelt zur Anmeldung': (
        (j) {
          j['auth'] = {
            'kind': 'customHeaders',
            'secretRefs': {'X-Room-Key2': 'r'},
          };
          j['headers'] = {'x-room-key2': 'a'};
        },
        'sieht geheim aus',
      ),
      'Header mit Zeilenumbruch': (
        (j) => j['headers'] = {'X-A': 'a\r\nX-B: c'},
        'Steuerzeichen',
      ),
      'Header mit Umlaut': ((j) => j['headers'] = {'X-A': 'Küche'}, 'ASCII'),
      'Header-Platzhalter kaputt': (
        (j) => j['headers'] = {'X-A': '{a'},
        'Platzhalter',
      ),
      'Body bei GET': ((j) => j['body'] = {'a': 1}, 'GET hat keinen Body'),
      'bodyFormat unbekannt': (
        (j) {
          j['method'] = 'POST';
          j['body'] = {'a': 1};
          j['bodyFormat'] = 'xml';
        },
        'bodyFormat',
      ),
      'Formular-Body kein Objekt': (
        (j) {
          j['method'] = 'POST';
          j['body'] = [1];
          j['bodyFormat'] = 'form';
        },
        'Formular-Body',
      ),
      'Formular-Body verschachtelt': (
        (j) {
          j['method'] = 'POST';
          j['body'] = {
            'a': {'b': 1},
          };
          j['bodyFormat'] = 'form';
        },
        'Formular-Body',
      ),
      'Risiko unbekannt': ((j) => j['risk'] = 'harmless', '„risk“'),
      'Zeitlimit 0': ((j) => j['timeoutSeconds'] = 0, 'Zeitlimit'),
      'Zeitlimit zu groß': ((j) => j['timeoutSeconds'] = 121, 'Zeitlimit'),
      'responsePath leer': ((j) => j['responsePath'] = '', 'responsePath'),
      'responsePath mit ..': (
        (j) => j['responsePath'] = 'a..b',
        'responsePath',
      ),
      'OAuth nicht unterstützt': (
        (j) => j['auth'] = {
          'kind': 'oauthPkce',
          'clientId': 'c',
          'authorizationUrl': 'https://a',
          'tokenUrl': 'https://t',
          'scopes': <String>[],
          'tokenSecretRef': 'r',
        },
        'OAuth',
      ),
      'Anmeldung kaputt': ((j) => j['auth'] = {'kind': 'magic'}, 'Anmeldung'),
      'ApiKey-Header ungültig': (
        (j) => j['auth'] = {
          'kind': 'apiKey',
          'secretRef': 'r',
          'headerName': 'X A',
        },
        'ungültiger Header-Name',
      ),
      'Custom-Header reserviert (Großschreibung)': (
        (j) => j['auth'] = {
          'kind': 'customHeaders',
          'secretRefs': {'Content-Length': 'r'},
        },
        'ungültiger Header-Name',
      ),
      'Custom-Header reserviert': (
        (j) => j['auth'] = {
          'kind': 'customHeaders',
          'secretRefs': {'host': 'r'},
        },
        'ungültiger Header-Name',
      ),
      'sensitive falscher Typ': ((j) => j['sensitive'] = 'ja', '„sensitive“'),
    };
    for (final MapEntry(key: name, value: (mutate, message)) in cases.entries) {
      test(name, () {
        final json = base();
        mutate(json);
        expect(
          () => HttpToolDefinition.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains(message), startsWith('HTTP-Tool')),
            ),
          ),
        );
      });
    }

    test('Liste: doppelte Namen und Ids', () {
      expect(
        () => validateHttpToolSet([def(name: 'a'), def(name: 'A')]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            contains('Name doppelt'),
          ),
        ),
      );
      final twin = HttpToolDefinition.fromJson({
        ...roundTrip(def(name: 'a').toJson()),
        'name': 'b',
      });
      expect(
        () => validateHttpToolSet([def(name: 'a'), twin]),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'm', contains('Id')),
        ),
      );
    });

    test('Export-Dokument: Version und Liste', () {
      expect(
        () => importHttpTools({'httpTools': <Object?>[]}),
        throwsFormatException,
      );
      expect(
        () => importHttpTools({'schemaVersion': 2, 'httpTools': <Object?>[]}),
        throwsFormatException,
      );
      expect(
        () => importHttpTools({'schemaVersion': 1}),
        throwsFormatException,
      );
      expect(
        () => importHttpTools({
          'schemaVersion': 1,
          'httpTools': [1],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            contains('Eintrag 1'),
          ),
        ),
      );
      expect(
        importHttpTools({'schemaVersion': 1, 'httpTools': <Object?>[]}),
        isEmpty,
      );
    });

    test('Heimnetz-Markierung erlaubt http zu beliebigem Namen', () {
      def(url: 'http://nas.example.org/{id}', homeNetwork: true).validate();
      def(url: 'http://192.168.1.2/{id}').validate();
      def(url: 'http://homeserver.tail1.ts.net/{id}').validate();
    });
  });

  group('Risiko', () {
    test('Vorschlag nach Methode', () {
      expect(HttpMethod.get.suggestedRisk, RiskLevel.read);
      expect(HttpMethod.head.suggestedRisk, RiskLevel.read);
      expect(HttpMethod.post.suggestedRisk, RiskLevel.write);
      expect(HttpMethod.put.suggestedRisk, RiskLevel.write);
      expect(HttpMethod.patch.suggestedRisk, RiskLevel.write);
      expect(HttpMethod.delete.suggestedRisk, RiskLevel.external);
      for (final m in HttpMethod.values) {
        expect(
          def(method: m, url: 'https://api.example.org/{id}').risk,
          m.suggestedRisk,
        );
      }
    });

    test('Override nur verschärfend (Tabelle)', () {
      for (final m in HttpMethod.values) {
        for (final r in RiskLevel.values) {
          for (final autoRun in [false, true]) {
            final d = def(
              method: m,
              risk: r,
              url: 'https://api.example.org/',
              autoRun: autoRun,
            );
            final raised = r.index >= m.suggestedRisk.index
                ? r
                : m.suggestedRisk;
            final why = '${m.verb} + ${r.name} + autoRun $autoRun';
            expect(
              d.effectiveRisk.index,
              greaterThanOrEqualTo(raised.index),
              reason: why,
            );
            expect(
              d.effectiveRisk.index,
              greaterThanOrEqualTo(m.suggestedRisk.index),
              reason: why,
            );
          }
        }
      }
      // Lockern ist wirkungslos: DELETE bleibt external, POST bleibt
      // mindestens write (ohne autoRun sogar bestätigt).
      expect(
        def(method: HttpMethod.delete, risk: RiskLevel.read).effectiveRisk,
        RiskLevel.external,
      );
      expect(
        def(
          method: HttpMethod.post,
          risk: RiskLevel.read,
          autoRun: true,
        ).effectiveRisk,
        RiskLevel.external,
        reason: 'autoRun nur, wenn auch die Nutzerwahl write ist',
      );
      expect(def(risk: RiskLevel.external).effectiveRisk, RiskLevel.external);
    });

    test('write ohne Undo: bestätigt, außer autoRun bei Vorschlag und Wahl '
        'write (Tabelle)', () {
      // (Methode, Nutzerwahl, autoRun) → effektive Stufe
      const w = RiskLevel.write;
      const e = RiskLevel.external;
      const r = RiskLevel.read;
      final table = <(HttpMethod, RiskLevel, bool, RiskLevel)>[
        (HttpMethod.get, r, false, r),
        (HttpMethod.get, r, true, r),
        (HttpMethod.head, r, true, r),
        // Nutzer verschärft GET auf write: kein Undo → bestätigt, autoRun
        // wirkt nicht (Vorschlag ist read).
        (HttpMethod.get, w, false, e),
        (HttpMethod.get, w, true, e),
        (HttpMethod.get, e, true, e),
        (HttpMethod.post, w, false, e),
        (HttpMethod.post, w, true, w),
        (HttpMethod.put, w, false, e),
        (HttpMethod.put, w, true, w),
        (HttpMethod.patch, w, false, e),
        (HttpMethod.patch, w, true, w),
        // Wahl unter dem Vorschlag zählt als write, autoRun wirkt nicht.
        (HttpMethod.post, r, true, e),
        (HttpMethod.post, r, false, e),
        (HttpMethod.post, e, true, e),
        (HttpMethod.delete, w, true, e),
        (HttpMethod.delete, e, true, e),
        (HttpMethod.delete, r, true, e),
      ];
      for (final (method, risk, autoRun, expected) in table) {
        final d = def(
          method: method,
          risk: risk,
          autoRun: autoRun,
          url: 'https://api.example.org/',
        );
        expect(
          d.effectiveRisk,
          expected,
          reason: '${method.verb} + ${risk.name} + autoRun $autoRun',
        );
        expect(
          d.autoRunApplies,
          method.suggestedRisk == w && risk == w,
          reason: '${method.verb} + ${risk.name}',
        );
      }
    });

    test('autoRun: JSON-Rundreise, alte Definitionen ohne Feld → false', () {
      final on = def(
        method: HttpMethod.post,
        risk: RiskLevel.write,
        autoRun: true,
        url: 'https://api.example.org/',
      );
      final json = roundTrip(on.toJson());
      expect(json['autoRun'], isTrue);
      expect(json['schemaVersion'], 1);
      final back = HttpToolDefinition.fromJson(json);
      expect(back.autoRun, isTrue);
      expect(back, on);
      expect(back.effectiveRisk, RiskLevel.write);

      final old = roundTrip(on.toJson())..remove('autoRun');
      final legacy = HttpToolDefinition.fromJson(old);
      expect(legacy.autoRun, isFalse);
      expect(legacy.effectiveRisk, RiskLevel.external);
      expect(on.copyWith(autoRun: false).toJson(), isNot(contains('autoRun')));
      expect(on.copyWith(autoRun: false) == on, isFalse);
      expect(
        () => HttpToolDefinition.fromJson({...json, 'autoRun': 'ja'}),
        throwsFormatException,
      );
    });

    test('Methode aus Text', () {
      expect(HttpMethod.parse(' delete '), HttpMethod.delete);
      expect(() => HttpMethod.parse('TRACE'), throwsFormatException);
      expect(HttpMethod.get.allowsBody, isFalse);
      expect(HttpMethod.delete.allowsBody, isTrue);
    });
  });

  test('geheime Header-Namen', () {
    for (final n in [
      'Authorization',
      'proxy-authorization',
      'Cookie',
      'X-Api-Key',
      'X-Auth-Token',
      'apikey',
      'X-Secret',
      'X-Session-Id',
      'X-Hub-Signature',
      'X-Key',
      'Ocp-Apim-Subscription-Key',
      'X-Bearer',
      'X-Credential',
      'X-Client-Secret',
      'Session',
    ]) {
      expect(isSecretHeaderName(n), isTrue, reason: n);
    }
    for (final n in ['Accept', 'X-Room', 'Content-Type', 'X-Request-Id']) {
      expect(isSecretHeaderName(n), isFalse, reason: n);
    }
  });
}
