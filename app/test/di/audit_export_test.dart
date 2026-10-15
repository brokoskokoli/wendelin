import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/audit_export.dart';

void main() {
  test('Export lässt Texte, Argumente und Beschreibungen weg', () {
    final json = jsonEncode([
      {
        'id': 1,
        'at': '2026-01-01T00:00:00Z',
        'kind': 'request',
        'sessionId': 's',
        'payload': {'source': 'voice', 'text': 'geheim', 'language': 'de'},
      },
      {
        'id': 2,
        'kind': 'toolCall',
        'payload': {'tool': 't', 'arguments': '{"q":"geheim"}', 'status': 'ok'},
      },
      {
        'id': 3,
        'kind': 'confirmation',
        'payload': {'tool': 't', 'description': 'geheim', 'approved': true},
      },
    ]);
    final out = auditExportWithoutContent(json);
    expect(out, isNot(contains('geheim')));
    final rows = jsonDecode(out) as List<Object?>;
    expect(rows, hasLength(3));
    expect((rows[0]! as Map)['payload'], {'source': 'voice', 'language': 'de'});
    expect((rows[1]! as Map)['payload'], {'tool': 't', 'status': 'ok'});
  });

  test('Export: nur Positivliste, unbekannte Felder und Freitexte fehlen', () {
    final json = jsonEncode([
      {
        'kind': 'error',
        'payload': {
          'error': 'network',
          'message': 'geheim',
          'zusatz': 'geheim',
        },
      },
      {
        'kind': 'verification',
        'payload': {'profileId': 'p', 'status': 'red', 'detail': 'geheim'},
      },
      {
        'kind': 'routing',
        'payload': {'profileId': 'p', 'modelId': 'm', 'reason': 'geheim'},
      },
      {
        'kind': 'neueArt',
        'payload': {'x': 'geheim'},
      },
    ]);
    final out = auditExportWithoutContent(json);
    expect(out, isNot(contains('geheim')));
    final rows = jsonDecode(out) as List<Object?>;
    expect((rows[0]! as Map)['payload'], {'error': 'network'});
    expect((rows[1]! as Map)['payload'], {'profileId': 'p', 'status': 'red'});
    expect((rows[2]! as Map)['payload'], {'profileId': 'p', 'modelId': 'm'});
    expect((rows[3]! as Map)['payload'], isEmpty);
  });
}
