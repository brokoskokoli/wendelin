import 'dart:convert';

import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Maps every contract scenario onto a script for [FakeLlmProvider].
ScriptedTurn turnFor(ContractScenario scenario) => switch (scenario) {
  ContractScenario.text => ScriptedTurn.text(
    ContractExpectations.text,
    thinking: 'Begrüßung formulieren',
    thinkingSignature: 'sig',
  ),
  ContractScenario.toolCall => ScriptedTurn.toolCalls([
    ToolCallBlock(
      id: 'call_1',
      name: ContractExpectations.toolName,
      argumentsJson: jsonEncode(ContractExpectations.singleCallArgs),
    ),
  ]),
  ContractScenario.parallelToolCalls => ScriptedTurn.toolCalls([
    for (final (i, args) in ContractExpectations.parallelCallArgs.indexed)
      ToolCallBlock(
        id: 'call_$i',
        name: ContractExpectations.toolName,
        argumentsJson: jsonEncode(args),
      ),
  ], text: 'Ich rufe zwei Tools auf.'),
  ContractScenario.serverError => ScriptedTurn.error(
    const ServerException('überlastet', statusCode: 529),
    partialText: 'Hal',
  ),
  ContractScenario.authError => ScriptedTurn.error(
    const AuthException('Schlüssel ungültig'),
  ),
  ContractScenario.rateLimited => ScriptedTurn.error(
    const RateLimitException('zu viele', retryAfter: Duration(seconds: 2)),
  ),
  ContractScenario.errorDuringToolCall => ScriptedTurn.errorDuringToolCall(
    ToolCallBlock(
      id: 'call_1',
      name: ContractExpectations.toolName,
      argumentsJson: jsonEncode(ContractExpectations.singleCallArgs),
    ),
    const ServerException('Verbindung abgerissen', statusCode: 500),
  ),
  ContractScenario.hang => ScriptedTurn.hang(partialText: 'Ich denke …'),
};

void main() {
  llmProviderContract(
    (scenario) => FakeLlmProvider([turnFor(scenario)]),
    name: 'FakeLlmProvider',
  );

  llmProviderContract(
    (scenario) => FakeLlmProvider([
      turnFor(scenario),
    ], eventDelay: const Duration(milliseconds: 1)),
    name: 'FakeLlmProvider mit Verzögerung',
  );
}
