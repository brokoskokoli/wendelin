import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// The contract checker must reject broken streams – otherwise the contract
/// suite would let broken adapters pass.
void main() {
  const call0 = ToolCallBlock(id: 'a', name: 'x__y', argumentsJson: '{"v":1}');
  const call1 = ToolCallBlock(id: 'b', name: 'x__y', argumentsJson: '{"v":2}');
  const usage = UsageEvent(Usage(inputTokens: 1));
  const done = Done(StopReason.endTurn);

  final valid = <String, List<ChatEvent>>{
    'text': [const TextDelta('a'), usage, done],
    'provider block between text': [
      const TextDelta('Ich suche. '),
      const ProviderBlockComplete(
        ProviderBlock(provider: 'anthropic', rawJson: '{}'),
      ),
      const TextDelta('Gefunden.'),
      usage,
      const Done(StopReason.pauseTurn),
    ],
    'error only': [const ErrorEvent(AuthException('x'))],
    'tool calls with deltas': [
      const ToolCallDelta(
        index: 0,
        id: 'a',
        name: 'x__y',
        argumentsFragment: '{"v"',
      ),
      const ToolCallDelta(index: 0, argumentsFragment: ':1}'),
      const ToolCallComplete(call0),
      const ToolCallDelta(index: 1, id: 'b', argumentsFragment: '{"v":2}'),
      const ToolCallComplete(call1),
      usage,
      const Done(StopReason.toolUse),
    ],
    'tool call without deltas': [
      const ToolCallComplete(call0),
      const Done(StopReason.toolUse),
    ],
    'only empty fragments': [
      const ToolCallDelta(index: 0, id: 'a'),
      const ToolCallComplete(call0),
      const Done(StopReason.toolUse),
    ],
    'incomplete call allowed when stream fails': [
      const ToolCallDelta(index: 0, id: 'a', argumentsFragment: '{"v"'),
      const ErrorEvent(NetworkException('weg')),
    ],
    'complete call plus incomplete second call on cancel': [
      const ToolCallDelta(index: 0, argumentsFragment: '{"v":1}'),
      const ToolCallComplete(call0),
      const ToolCallDelta(index: 1, id: 'b', argumentsFragment: '{'),
      const ErrorEvent(CancelledException()),
    ],
    'thinking deltas match complete block': [
      const ThinkingDelta('Ich '),
      const ThinkingDelta('denke'),
      const ThinkingComplete(ThinkingBlock('Ich denke', signature: 's')),
      const ThinkingDelta('zwei'),
      const ThinkingComplete(ThinkingBlock('zwei')),
      done,
    ],
    'open thinking block allowed when stream fails': [
      const ThinkingDelta('Ich den'),
      const ErrorEvent(NetworkException('weg')),
    ],
    'redacted thinking without deltas': [
      const ThinkingComplete(ThinkingBlock.redacted('opak')),
      done,
    ],
    'deltas reassemble to equivalent JSON': [
      const ToolCallDelta(index: 0, argumentsFragment: '{ "v" : 1 }'),
      const ToolCallComplete(call0),
      done,
    ],
  };

  final invalid = <String, List<ChatEvent>>{
    'empty': [],
    'no terminal event': [const TextDelta('a'), usage],
    'two Done': [done, done],
    'Done then Error': [done, const ErrorEvent(NetworkException('x'))],
    'event after Done': [done, const TextDelta('a')],
    'usage after Done is impossible but usage after terminal Error': [
      const ErrorEvent(NetworkException('x')),
      usage,
    ],
    'delta after its complete': [
      const ToolCallComplete(call0),
      const ToolCallDelta(index: 0, argumentsFragment: '{"v":1}'),
      done,
    ],
    'delta index without complete': [
      const ToolCallDelta(index: 1, argumentsFragment: '{}'),
      const ToolCallComplete(call0),
      done,
    ],
    'delta id differs from call id': [
      const ToolCallDelta(index: 0, id: 'zzz', argumentsFragment: '{"v":1}'),
      const ToolCallComplete(call0),
      done,
    ],
    'delta name differs from call name': [
      const ToolCallDelta(
        index: 0,
        name: 'other',
        argumentsFragment: '{"v":1}',
      ),
      const ToolCallComplete(call0),
      done,
    ],
    'incomplete call although stream ends with Done': [
      const ToolCallDelta(index: 0, id: 'a', argumentsFragment: '{"v"'),
      done,
    ],
    'delta after its complete even when failing': [
      const ToolCallComplete(call0),
      const ToolCallDelta(index: 0, argumentsFragment: '{"v":1}'),
      const ErrorEvent(NetworkException('x')),
    ],
    'thinking deltas without ThinkingComplete before Done': [
      const ThinkingDelta('Ich denke'),
      const TextDelta('Antwort'),
      done,
    ],
    'thinking deltas differ from complete block': [
      const ThinkingDelta('Ich denke'),
      const ThinkingComplete(ThinkingBlock('Etwas anderes')),
      done,
    ],
    'fragments do not match arguments': [
      const ToolCallDelta(index: 0, argumentsFragment: '{"v":2}'),
      const ToolCallComplete(call0),
      done,
    ],
  };

  group('expectWellFormedChatStream accepts', () {
    valid.forEach((name, events) {
      test(name, () => expectWellFormedChatStream(events));
    });
  });

  group('expectWellFormedChatStream rejects', () {
    invalid.forEach((name, events) {
      test(name, () {
        expect(
          () => expectWellFormedChatStream(events),
          throwsA(isA<TestFailure>()),
        );
      });
    });
  });
}
