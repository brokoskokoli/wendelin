import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  final image = ImageBlock(mediaType: 'image/png', bytes: [137, 80, 78, 71]);
  const call = ToolCallBlock(
    id: 'toolu_1',
    name: 'calendar__create_event',
    argumentsJson: '{"title":"Tauchen"}',
  );

  final conversation = <Message>[
    Message.system('Du bist Wendelin.'),
    Message.user('Trag mir morgen um 10 Tauchen ein', images: [image]),
    Message.assistant([
      const ThinkingBlock('Termin anlegen', signature: 'abc'),
      const TextBlock('Mache ich.'),
      call,
    ]),
    Message.toolResults([
      ToolResultBlock(callId: 'toolu_1', content: const [TextBlock('ok')]),
    ]),
    Message.assistantText('Eingetragen: Tauchen, Di 10:00.'),
    Message(Role.user, const []),
  ];

  group('Message JSON round trip', () {
    for (final (i, m) in conversation.indexed) {
      test('#$i ${m.role.name}', () {
        final json = jsonDecode(jsonEncode(m.toJson())) as Map<String, Object?>;
        final decoded = Message.fromJson(json);
        expect(decoded, m);
        expect(decoded.hashCode, m.hashCode);
      });
    }

    test('whole conversation as JSON list', () {
      final encoded = jsonEncode([for (final m in conversation) m.toJson()]);
      final decoded = [
        for (final j in jsonDecode(encoded) as List<Object?>)
          Message.fromJson(j! as Map<String, Object?>),
      ];
      expect(decoded, conversation);
    });

    test('format', () {
      expect(Message.assistantText('x').toJson(), {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'x'},
        ],
      });
    });
  });

  group('Message.fromJson rejects bad input', () {
    final cases = <String, Map<String, Object?>>{
      'unknown role': {'role': 'robot', 'content': <Object?>[]},
      'missing role': {'content': <Object?>[]},
      'missing content': {'role': 'user'},
      'content not list': {'role': 'user', 'content': 'hi'},
      'bad block': {
        'role': 'user',
        'content': [
          {'type': '?'},
        ],
      },
    };
    cases.forEach((name, json) {
      test(name, () {
        expect(() => Message.fromJson(json), throwsFormatException);
      });
    });
  });

  group('constructors', () {
    test('user puts images before text', () {
      final m = Message.user('Was ist das?', images: [image]);
      expect(m.role, Role.user);
      expect(m.content, [image, const TextBlock('Was ist das?')]);
    });
    test('roles', () {
      expect(Message.system('s').role, Role.system);
      expect(Message.user('u').role, Role.user);
      expect(Message.assistantText('a').role, Role.assistant);
      expect(Message.assistant(const []).role, Role.assistant);
      expect(Message.toolResults(const []).role, Role.tool);
    });
  });

  test('text concatenates text blocks only', () {
    final m = Message.assistant([
      const TextBlock('Hallo '),
      const ThinkingBlock('nicht anzeigen'),
      call,
      const TextBlock('Welt'),
    ]);
    expect(m.text, 'Hallo Welt');
    expect(m.toolCalls, [call]);
    expect(Message.user('x').toolCalls, isEmpty);
  });

  test('content is copied and unmodifiable', () {
    final blocks = <ContentBlock>[const TextBlock('a')];
    final m = Message(Role.user, blocks);
    blocks.add(const TextBlock('b'));
    expect(m.content, hasLength(1));
    expect(() => m.content.add(const TextBlock('c')), throwsUnsupportedError);
  });

  test('equality depends on role and content', () {
    expect(Message.user('a'), Message.user('a'));
    expect(Message.user('a'), isNot(Message.user('b')));
    expect(
      Message.user('a'),
      isNot(Message(Role.assistant, [const TextBlock('a')])),
    );
    expect(Message.user('a').toString(), contains('user'));
  });

  test('privacy floor: JSON, equality, copy', () {
    final m = Message.user('privat: Befund').withPrivacyFloor(PrivacyLevel.tee);
    expect(m.privacyFloor, PrivacyLevel.tee);
    expect(m.toJson()['privacyFloor'], 'tee');
    expect(Message.fromJson(m.toJson()), m);
    expect(Message.user('a').toJson().containsKey('privacyFloor'), isFalse);
    expect(Message.fromJson(Message.user('a').toJson()).privacyFloor, isNull);
    expect(m, isNot(Message.user('privat: Befund')));
    expect(m.hashCode, isNot(Message.user('privat: Befund').hashCode));
    expect(m.withPrivacyFloor(null), Message.user('privat: Befund'));
    expect(m.toString(), contains('floor: tee'));
    expect(
      () => Message.fromJson({...m.toJson(), 'privacyFloor': 'geheim'}),
      throwsFormatException,
    );
  });
}
