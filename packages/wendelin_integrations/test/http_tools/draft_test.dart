import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'repo_support.dart';

void main() {
  group('HttpToolDraft', () {
    HttpToolDraft draft() => HttpToolDraft.empty('d1')
      ..name = 'ha_licht'
      ..description = 'Licht schalten'
      ..url = 'https://ha.example.org/api/{raum}'
      ..args = [
        HttpArgDraft(name: 'raum', required: true, description: 'Raum'),
      ];

    test('effectiveRisk des Entwurfs gleich dem der Definition', () {
      for (final m in HttpMethod.values) {
        for (final r in RiskLevel.values) {
          for (final auto in [false, true]) {
            final d = draft()
              ..setMethod(m)
              ..risk = r
              ..autoRun = auto;
            expect(
              d.effectiveRisk,
              d.toDefinition().effectiveRisk,
              reason: '${m.verb} ${r.name} autoRun=$auto',
            );
          }
        }
      }
    });

    test('Liste ergibt JSON-Schema, Rundreise über die Definition', () {
      final d = draft()
        ..setMethod(HttpMethod.post)
        ..body = '{"an": "{an}"}'
        ..args.add(HttpArgDraft(name: 'an', type: 'boolean'))
        ..headers = [HttpHeaderDraft(name: 'X-Raum', value: '{raum}')]
        ..auth = HttpAuthKind.headers
        ..secretHeaders = [
          HttpSecretHeaderDraft(name: 'X-Api-Key', newValue: httpCanary),
        ]
        ..autoRun = true
        ..risk = RiskLevel.write;
      expect(d.problem(const []), isNull);
      final def = d.toDefinition();
      expect(def.inputSchema, {
        'type': 'object',
        'properties': {
          'raum': {'type': 'string', 'description': 'Raum'},
          'an': {'type': 'boolean'},
        },
        'required': ['raum'],
      });
      expect(def.autoRun, isTrue);
      expect(def.effectiveRisk, RiskLevel.write);
      expect(jsonEncode(def.toJson()), isNot(contains(httpCanary)));
      expect(d.secretChanges(), {'d1.h.x-api-key': httpCanary});

      final back = HttpToolDraft.of(def, storedRefs: {'d1.h.x-api-key'});
      expect(back.rawSchema, isFalse);
      expect(back.args.map((a) => a.name), ['raum', 'an']);
      expect(back.secretHeaders.single.stored, isTrue);
      expect(back.secretChanges(), isEmpty);
      expect(back.toDefinition(), def);
    });

    test('autoRun nur bei Methode und Wahl write', () {
      final d = draft()
        ..autoRun = true
        ..risk = RiskLevel.write;
      expect(d.autoRunAvailable, isFalse, reason: 'GET');
      expect(d.toDefinition().autoRun, isFalse);
      expect(d.toDefinition().effectiveRisk, RiskLevel.external);
      d.setMethod(HttpMethod.put);
      expect(d.risk, RiskLevel.write, reason: 'Vorschlag nach Methode');
      expect(d.riskChoices, [RiskLevel.write, RiskLevel.external]);
      expect(d.toDefinition().autoRun, isTrue);
      d.risk = RiskLevel.external;
      expect(d.toDefinition().autoRun, isFalse);
    });

    test('Validierung: Name, Platzhalter ohne Argument, im Host', () {
      expect((draft()..name = '').nameError(const []), 'Name fehlt');
      expect(
        (draft()..name = 'mit punkt.').nameError(const []),
        startsWith('Nur Buchstaben'),
      );
      expect((draft()..name = 'x' * 59).nameError(const []), contains('58'));
      expect(draft().nameError(const ['HA_LICHT']), 'Name ist schon vergeben');
      expect(
        (draft()..url = 'https://ha.example.org/{fehlt}').problem(const []),
        'Platzhalter „{fehlt}“ ist kein Argument im Schema',
      );
      expect(
        (draft()..url = 'https://{raum}.example.org/').problem(const []),
        contains('Host'),
      );
      expect(
        (draft()..url = 'http://api.example.org/').problem(const []),
        contains('Heimnetz'),
      );
      expect(
        (draft()..description = ' ').problem(const []),
        contains('Beschreibung'),
      );
      expect(
        (draft()..timeoutSeconds = 'x').problem(const []),
        contains('Zeitlimit'),
      );
      expect((draft()..body = '{').problem(const []), contains('Body'));
      expect(
        (draft()..args.add(HttpArgDraft(name: 'raum'))).problem(const []),
        contains('doppelt'),
      );
      expect(
        (draft()..auth = HttpAuthKind.bearer).problem(const []),
        'Bearer-Token fehlt',
      );
      expect(
        (draft()
              ..auth = HttpAuthKind.headers
              ..secretHeaders = [HttpSecretHeaderDraft(name: 'X-K')])
            .problem(const []),
        'Wert für „X-K“ fehlt',
      );
      expect(
        (draft()
              ..headers = [HttpHeaderDraft(name: 'Authorization', value: 'x')])
            .problem(const []),
        contains('geheim'),
      );
    });

    test('Rohmodus für Schemas, die die Liste nicht abbildet', () {
      final def = draft().toDefinition().copyWith(
        inputSchema: {
          'type': 'object',
          'properties': {
            'raum': {
              'type': 'string',
              'enum': ['bad', 'flur'],
            },
          },
        },
      );
      final d = HttpToolDraft.of(def);
      expect(d.rawSchema, isTrue);
      expect(d.argNames(), {'raum'});
      expect(d.argTypes(), {'raum': 'string'});
      expect(d.toDefinition().inputSchema, def.inputSchema);
      d.schemaText = '[';
      expect(d.problem(const []), 'Schema ist kein gültiges JSON');
      expect(d.argNames(), isEmpty);
      d.schemaText = '[]';
      expect(d.problem(const []), 'Schema muss ein JSON-Objekt sein');
    });

    test('Bearer und Testargumente', () {
      final d = draft()
        ..auth = HttpAuthKind.bearer
        ..bearerNew = httpCanary;
      expect(d.toDefinition().auth, ApiKeyAuth(httpBearerRef('d1')));
      expect(d.secretChanges(), {'d1.bearer': httpCanary});
      expect(
        HttpToolDraft.of(
          d.toDefinition(),
          storedRefs: {'d1.bearer'},
        ).bearerStored,
        isTrue,
      );
      expect(parseHttpArg(' 3 ', 'integer'), 3);
      expect(parseHttpArg('2,5', 'number'), 2.5);
      expect(parseHttpArg('ja', 'boolean'), isTrue);
      expect(parseHttpArg('nein', 'boolean'), isFalse);
      expect(parseHttpArg('', 'string'), isNull);
      expect(() => parseHttpArg('x', 'integer'), throwsFormatException);
      expect(() => parseHttpArg('x', 'number'), throwsFormatException);
      expect(
        () => parseHttpArg('vielleicht', 'boolean'),
        throwsFormatException,
      );
      expect(stripHttpToolPrefix('HTTP-Tool „a“: kaputt'), 'kaputt');
    });
  });
}
