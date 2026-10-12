import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/credentials.dart';
import '../common/health_probe.dart';
import '../common/http_settings.dart';
import '../common/http_transport.dart';
import '../common/json_util.dart';
import '../common/redactor.dart';
import 'openai_errors.dart';
import 'openai_options.dart';
import 'openai_request.dart';
import 'openai_stream_decoder.dart';

/// [LlmProvider] for OpenAI Chat Completions and compatible servers
/// (OpenRouter, Mistral, Phala/RedPill, Tinfoil, Ollama, vLLM, …).
///
/// [baseUrl] includes the version path, e.g. `https://api.openai.com/v1`.
final class OpenAiChatAdapter implements LlmProvider {
  /// Creates the adapter. [label] names the provider in error messages.
  OpenAiChatAdapter({
    required this.baseUrl,
    required this.credentials,
    required this.defaultModel,
    this.label = 'OpenAI-kompatibel',
    http.Client? client,
    Map<String, String> extraHeaders = const {},
    this.options = const OpenAiOptions(),
    this.capabilities = const ProviderCapabilities(
      tools: true,
      streaming: true,
    ),
    this.settings = const HttpSettings(),
  }) : _base = _trimSlash(baseUrl.toString()),
       _extraHeaders = Map.unmodifiable(extraHeaders),
       _transport = HttpTransport(
         client: client ?? defaultHttpClient(),
         settings: settings,
         label: label,
         redactor: Redactor(),
       );

  /// API root including the version path.
  final Uri baseUrl;

  /// Authentication (references only, resolved per request).
  final Credentials credentials;

  /// Model for [test].
  final String defaultModel;

  /// Provider name for error messages.
  final String label;

  /// Adapter options.
  final OpenAiOptions options;

  /// Reported as [caps] (depends on server and model).
  final ProviderCapabilities capabilities;

  /// Transport settings.
  final HttpSettings settings;

  final String _base;
  final Map<String, String> _extraHeaders;
  final HttpTransport _transport;

  /// Set once the server rejected `stream_options`.
  bool _usageOptionRejected = false;

  static String _trimSlash(String s) {
    var r = s;
    while (r.endsWith('/')) {
      r = r.substring(0, r.length - 1);
    }
    return r;
  }

  @override
  ProviderType get type => ProviderType.openaiCompatible;

  @override
  ProviderCapabilities get caps => capabilities;

  String get _maxTokensField =>
      options.maxTokensField ??
      (baseUrl.host == 'api.openai.com'
          ? 'max_completion_tokens'
          : 'max_tokens');

  Future<Map<String, String>> _headers() async => {
    ..._extraHeaders,
    ...await credentials.headers(_transport.redactor),
  };

  ProviderException _httpError(int status, String body, Duration? retry) {
    Map<String, Object?>? error;
    try {
      final decoded = asMap(jsonDecode(body));
      error = asMap(decoded?['error']) ?? decoded;
    } on FormatException {
      error = null;
    }
    return openAiError(
      error ?? {'message': errorDetail(body)},
      label: label,
      status: status,
      retryAfter: retry,
    );
  }

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      _transport.stream(
        cancel: cancel,
        decoder: () => OpenAiStreamDecoder(
          label: label,
          emitReasoning: options.emitReasoning,
        ),
        onHttpError: _httpError,
        retry: (status, body, attempt) {
          if (attempt == 0 &&
              options.includeUsage &&
              !_usageOptionRejected &&
              rejectsStreamOptions(status, body)) {
            _usageOptionRejected = true;
            return true;
          }
          return false;
        },
        build: (attempt, abortTrigger) async {
          final body = buildOpenAiBody(
            req,
            options,
            maxTokensField: _maxTokensField,
            includeUsage: options.includeUsage && !_usageOptionRejected,
          );
          return http.AbortableRequest(
              'POST',
              Uri.parse('$_base/chat/completions'),
              abortTrigger: abortTrigger,
            )
            ..headers.addAll(await _headers())
            ..headers['content-type'] = 'application/json'
            ..headers['accept'] = 'text/event-stream'
            ..body = jsonEncode(body);
        },
      );

  @override
  Future<List<ModelInfo>> listModels() async {
    final json = await _transport.getJson(
      Uri.parse('$_base/models'),
      await _headers(),
      onHttpError: _httpError,
    );
    return [
      for (final entry in asList(json['data']))
        if (asMap(entry) case final m?)
          if (asString(m['id']) case final id?)
            if (!options.teeModelsOnly || m['is_tee'] == true)
              ModelInfo(
                id: id,
                displayName: asString(m['name']),
                contextWindow:
                    asInt(m['context_length']) ?? asInt(m['context_window']),
                supportsTools: _supportsTools(m),
              ),
    ];
  }

  static bool? _supportsTools(Map<String, Object?> model) {
    final params = model['supported_parameters'];
    return params is List<Object?> ? params.contains('tools') : null;
  }

  @override
  Future<HealthCheck> test() => runHealthProbe(
    provider: this,
    model: defaultModel,
    clock: settings.clock,
    baseCaps: caps,
  );

  @override
  String toString() => 'OpenAiChatAdapter($label, $_base, $defaultModel)';
}
