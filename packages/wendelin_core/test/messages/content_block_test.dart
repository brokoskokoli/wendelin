import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Encodes through a real JSON string to catch non-JSON values.
Object? viaJsonString(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json));

void main() {
  final image = ImageBlock(mediaType: 'image/png', bytes: [0, 1, 2, 250, 255]);
  final blocks = <String, ContentBlock>{
    'text': const TextBlock('Hallo Welt – äöü 🙂'),
    'empty text': const TextBlock(''),
    'image': image,
    'toolCall': const ToolCallBlock(
      id: 'call_1',
      name: 'calendar__create_event',
      argumentsJson: '{"title":"Tauchen","start":"2026-10-13T10:00:00"}',
    ),
    'toolCall invalid json': const ToolCallBlock(
      id: 'c2',
      name: 'x',
      argumentsJson: '{kaputt',
    ),
    'toolResult': ToolResultBlock(
      callId: 'call_1',
      content: [const TextBlock('angelegt'), image],
    ),
    'toolResult error': ToolResultBlock(
      callId: 'call_2',
      content: [const TextBlock('Kalender nicht gefunden')],
      isError: true,
    ),
    'toolResult empty': ToolResultBlock(callId: 'c3', content: const []),
    'thinking': const ThinkingBlock('Ich überlege', signature: 'sig=='),
    'thinking unsigned': const ThinkingBlock('Nur Text'),
  };

  group('ContentBlock JSON round trip', () {
    blocks.forEach((name, block) {
      test(name, () {
        final decoded = ContentBlock.fromJson(
          viaJsonString(block.toJson())! as Map<String, Object?>,
        );
        expect(decoded, block);
        expect(decoded.runtimeType, block.runtimeType);
        expect(decoded.hashCode, block.hashCode);
      });
    });
  });

  group('ContentBlock JSON format is stable', () {
    test('text', () {
      expect(const TextBlock('a').toJson(), {'type': 'text', 'text': 'a'});
    });
    test('image as base64', () {
      expect(ImageBlock(mediaType: 'image/png', bytes: [1, 2, 3]).toJson(), {
        'type': 'image',
        'mediaType': 'image/png',
        'data': 'AQID',
      });
    });
    test('toolCall', () {
      expect(
        const ToolCallBlock(id: 'i', name: 'n', argumentsJson: '{}').toJson(),
        {'type': 'toolCall', 'id': 'i', 'name': 'n', 'argumentsJson': '{}'},
      );
    });
    test('toolResult', () {
      expect(
        ToolResultBlock(
          callId: 'i',
          content: const [TextBlock('x')],
          isError: true,
        ).toJson(),
        {
          'type': 'toolResult',
          'callId': 'i',
          'content': [
            {'type': 'text', 'text': 'x'},
          ],
          'isError': true,
        },
      );
    });
    test('thinking omits missing signature', () {
      expect(const ThinkingBlock('t').toJson(), {
        'type': 'thinking',
        'text': 't',
      });
      expect(const ThinkingBlock('t', signature: 's').toJson(), {
        'type': 'thinking',
        'text': 't',
        'signature': 's',
      });
    });
  });

  group('ContentBlock.fromJson rejects bad input', () {
    final cases = <String, Map<String, Object?>>{
      'unknown type': {'type': 'video'},
      'missing type': {'text': 'x'},
      'type not string': {'type': 1},
      'text missing': {'type': 'text'},
      'text wrong type': {'type': 'text', 'text': 3},
      'image bad base64': {
        'type': 'image',
        'mediaType': 'image/png',
        'data': '%%%',
      },
      'toolCall missing args': {'type': 'toolCall', 'id': 'a', 'name': 'b'},
      'toolResult content not list': {
        'type': 'toolResult',
        'callId': 'a',
        'content': 'x',
        'isError': false,
      },
      'toolResult content element not object': {
        'type': 'toolResult',
        'callId': 'a',
        'content': ['x'],
        'isError': false,
      },
      'toolResult isError missing': {
        'type': 'toolResult',
        'callId': 'a',
        'content': <Object?>[],
      },
      'thinking signature wrong type': {
        'type': 'thinking',
        'text': 'a',
        'signature': 1,
      },
    };
    cases.forEach((name, json) {
      test(name, () {
        expect(() => ContentBlock.fromJson(json), throwsFormatException);
      });
    });
  });

  group('equality distinguishes every field', () {
    test('text', () {
      expect(const TextBlock('a'), isNot(const TextBlock('b')));
    });
    test('image', () {
      final a = ImageBlock(mediaType: 'image/png', bytes: [1, 2]);
      expect(a, ImageBlock(mediaType: 'image/png', bytes: [1, 2]));
      expect(a, isNot(ImageBlock(mediaType: 'image/jpeg', bytes: [1, 2])));
      expect(a, isNot(ImageBlock(mediaType: 'image/png', bytes: [1, 3])));
    });
    test('toolCall', () {
      const a = ToolCallBlock(id: 'i', name: 'n', argumentsJson: '{}');
      expect(
        a,
        isNot(const ToolCallBlock(id: 'j', name: 'n', argumentsJson: '{}')),
      );
      expect(
        a,
        isNot(const ToolCallBlock(id: 'i', name: 'm', argumentsJson: '{}')),
      );
      expect(
        a,
        isNot(const ToolCallBlock(id: 'i', name: 'n', argumentsJson: '[]')),
      );
    });
    test('toolResult', () {
      final a = ToolResultBlock(callId: 'i', content: const [TextBlock('x')]);
      expect(a, ToolResultBlock(callId: 'i', content: const [TextBlock('x')]));
      expect(
        a,
        isNot(ToolResultBlock(callId: 'j', content: const [TextBlock('x')])),
      );
      expect(
        a,
        isNot(ToolResultBlock(callId: 'i', content: const [TextBlock('y')])),
      );
      expect(
        a,
        isNot(
          ToolResultBlock(
            callId: 'i',
            content: const [TextBlock('x')],
            isError: true,
          ),
        ),
      );
    });
    test('thinking', () {
      expect(const ThinkingBlock('a'), isNot(const ThinkingBlock('b')));
      expect(
        const ThinkingBlock('a', signature: 's'),
        isNot(const ThinkingBlock('a')),
      );
    });
    test('different block types are never equal', () {
      expect(const TextBlock('a'), isNot(const ThinkingBlock('a')));
    });
  });

  group('ImageBlock', () {
    test('base64 factory decodes, base64Data encodes', () {
      final b = ImageBlock.base64(mediaType: 'image/jpeg', data: 'AQID');
      expect(b.bytes, [1, 2, 3]);
      expect(b.base64Data, 'AQID');
    });
    test('bytes are copied and unmodifiable', () {
      final source = [1, 2, 3];
      final b = ImageBlock(mediaType: 'image/png', bytes: source);
      source[0] = 9;
      expect(b.bytes.first, 1);
      expect(() => b.bytes[0] = 5, throwsUnsupportedError);
    });
  });

  group('ToolCallBlock.tryDecodeArguments', () {
    final cases = <String, Map<String, Object?>?>{
      '{"a":1,"b":[true,null]}': {
        'a': 1,
        'b': [true, null],
      },
      '{}': {},
      '[1,2]': null,
      '"text"': null,
      '{kaputt': null,
      '': null,
    };
    cases.forEach((input, expected) {
      test('"$input"', () {
        final call = ToolCallBlock(id: 'i', name: 'n', argumentsJson: input);
        expect(call.tryDecodeArguments(), expected);
      });
    });
  });

  test('ToolResultBlock content is unmodifiable', () {
    final r = ToolResultBlock(callId: 'i', content: [const TextBlock('x')]);
    expect(() => r.content.add(const TextBlock('y')), throwsUnsupportedError);
  });

  test('toString is informative', () {
    expect(const TextBlock('hi').toString(), contains('hi'));
    expect(
      ImageBlock(mediaType: 'image/png', bytes: [1]).toString(),
      contains('1 bytes'),
    );
    expect(
      const ToolCallBlock(id: 'i', name: 'n', argumentsJson: '{}').toString(),
      contains('n'),
    );
    expect(
      ToolResultBlock(callId: 'cid', content: const []).toString(),
      contains('cid'),
    );
    expect(const ThinkingBlock('denk').toString(), contains('denk'));
  });
}
