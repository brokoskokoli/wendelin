import 'package:wendelin_core/wendelin_core.dart';

/// Tool offered in the health check's mini request.
const healthProbeTool = ToolSpec(
  name: 'wendelin__ping',
  description: 'Verbindungstest. Rufe dieses Tool genau einmal auf.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'text': {'type': 'string'},
    },
    'required': ['text'],
  },
);

/// Runs the setup-dialog check shared by all adapters: load models, then a
/// mini request that asks for one call of [healthProbeTool]. Never throws.
///
/// [baseCaps] are the provider's static capabilities; `detected` reports
/// them with `tools` set to what the probe actually observed.
Future<HealthCheck> runHealthProbe({
  required LlmProvider provider,
  required String model,
  required Clock clock,
  required ProviderCapabilities baseCaps,
}) async {
  final start = clock.now();
  Duration elapsed() => clock.now().difference(start);

  List<ModelInfo>? models;
  try {
    models = await provider.listModels();
  } on AuthException catch (e) {
    return HealthCheck(ok: false, latency: elapsed(), message: e.message);
  } on ProviderException {
    models = null; // Some servers have no model list; the chat decides.
  }

  final request = ChatRequest(
    systemPrompt: 'Du bist ein Verbindungstest.',
    messages: [
      Message.user(
        'Rufe das Tool ${healthProbeTool.name} mit text="ok" auf. '
        'Antworte sonst nichts.',
      ),
    ],
    tools: const [healthProbeTool],
    model: model,
    maxTokens: 200,
  );
  var toolCalled = false;
  ProviderException? error;
  StopReason? stop;
  try {
    await for (final event in provider.chat(request)) {
      switch (event) {
        case ToolCallComplete(:final call)
            when call.name == healthProbeTool.name:
          toolCalled = true;
        case ErrorEvent(error: final e):
          error = e;
        case Done(:final stopReason):
          stop = stopReason;
        default:
          break;
      }
    }
  } on Object catch (e) {
    error = NetworkException('Test fehlgeschlagen: $e');
  }
  final latency = elapsed();
  final detected = ProviderCapabilities(
    tools: toolCalled,
    vision: baseCaps.vision,
    streaming: stop != null,
    promptCaching: baseCaps.promptCaching,
    tee: baseCaps.tee,
  );
  if (error != null) {
    return HealthCheck(
      ok: false,
      latency: latency,
      message: error.message,
      models: models,
    );
  }
  return HealthCheck(
    ok: true,
    latency: latency,
    message: toolCalled
        ? 'Verbindung ok, Tool-Aufruf funktioniert ($model)'
        : 'Verbindung ok, aber das Modell hat kein Tool aufgerufen ($model)',
    models: models,
    detected: detected,
  );
}
