import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';

/// `AgentController.submit`: the agent part of a voice request.
void main() {
  late ProviderContainer c;
  tearDown(() => c.dispose());

  AgentController controller() => c.read(agentControllerProvider.notifier);

  test('liefert die Ereignisse des Laufs bis AgentDone', () async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([ScriptedTurn.text('Hallo du.')]),
      ),
    );
    c = env.container();
    final events = await controller()
        .submit(
          UserInput(text: ' Hallo ', source: InputSource.voice),
          trigger: 'assistant',
        )
        .toList();
    expect(events.last, isA<AgentDone>());
    expect(
      events.whereType<AgentTextDelta>().map((e) => e.text).join(),
      'Hallo du.',
    );
    expect(
      c
          .read(agentControllerProvider)
          .entries
          .whereType<UserEntry>()
          .single
          .text,
      'Hallo',
    );
    await c.read(auditRecorderProvider).flush();
    final request = (await env.storage.audit.query()).firstWhere(
      (e) => e.kind == AuditKind.request,
    );
    expect(request.payload['trigger'], 'assistant');
    expect(request.payload['source'], 'voice');
  });

  test('während eines Laufs: sofort AgentFailed, kein zweiter Lauf', () async {
    final provider = FakeLlmProvider([ScriptedTurn.hang()]);
    c = TestEnv(providerConfig: scripted(provider)).container();
    final first = controller().submit(UserInput(text: 'eins'));
    final last = first.last;
    while (provider.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final second = await controller().submit(UserInput(text: 'zwei')).toList();
    expect(second.single, isA<AgentFailed>());
    expect((second.single as AgentFailed).message, contains('läuft schon'));
    controller().cancel();
    expect(await last, isA<AgentFailed>());
    expect(provider.requests, hasLength(1));
  });

  test('leerer Text: AgentFailed', () async {
    c = TestEnv().container();
    final events = await controller().submit(UserInput(text: '  ')).toList();
    expect((events.single as AgentFailed).message, 'Die Anfrage ist leer.');
  });

  test('ohne Provider: AgentFailed mit Hinweis', () async {
    c = TestEnv().container();
    final events = await controller().submit(UserInput(text: 'Hallo')).toList();
    final failed = events.single as AgentFailed;
    expect(failed.message, 'Bitte zuerst einen Provider einrichten.');
    expect(c.read(agentControllerProvider).running, isFalse);
  });

  test('Abbruch während des Starts: kein Modellaufruf', () async {
    final provider = FakeLlmProvider([ScriptedTurn.text('nie')]);
    c = TestEnv(providerConfig: scripted(provider)).container();
    final events = controller().submit(UserInput(text: 'Hallo')).toList();
    controller().cancel();
    final list = await events;
    expect((list.single as AgentFailed).error, AgentErrorKind.cancelled);
    expect(provider.requests, isEmpty);
    expect(c.read(agentControllerProvider).running, isFalse);
  });
}
