import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/credentials.dart';
import '../common/health_probe.dart';
import '../common/http_settings.dart';
import '../common/http_transport.dart';
import '../common/json_util.dart';
import '../common/redactor.dart';
import 'anthropic_errors.dart';
import 'anthropic_options.dart';
import 'anthropic_request.dart';
import 'anthropic_stream_decoder.dart';

/// [LlmProvider] for the Anthropic Messages API (`POST /v1/messages`,
/// streaming), incl. prompt caching, thinking and optional server-side web
/// search.
final class AnthropicMessagesAdapter implements LlmProvider {
  /// Creates the adapter. [baseUrl] defaults to [defaultBaseUrl] (with or
  /// without trailing `/v1`); [defaultModel] is used by [test].
  AnthropicMessagesAdapter({
    required this.credentials,
    required this.defaultModel,
    Uri? baseUrl,
    http.Client? client,
    Map<String, String> extraHeaders = const {},
    this.options = const AnthropicOptions(),
    this.settings = const HttpSettings(),
  }) : _base = _apiRoot(baseUrl ?? defaultBaseUrl),
       _extraHeaders = Map.unmodifiable(extraHeaders),
       _transport = HttpTransport(
         client: client ?? defaultHttpClient(),
         settings: settings,
         label: 'Anthropic',
         redactor: Redactor(),
       );

  /// Public Anthropic endpoint.
  static final defaultBaseUrl = Uri.parse('https://api.anthropic.com');

  /// Value of the `anthropic-version` header.
  static const apiVersion = '2023-06-01';

  /// Authentication (references only, resolved per request).
  final Credentials credentials;

  /// Model for [test].
  final String defaultModel;

  /// Adapter options (web search, thinking, caching).
  final AnthropicOptions options;

  /// Transport settings.
  final HttpSettings settings;

  final String _base;
  final Map<String, String> _extraHeaders;
  final HttpTransport _transport;

  static String _apiRoot(Uri base) {
    var s = base.toString();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s.endsWith('/v1') ? s : '$s/v1';
  }

  @override
  ProviderType get type => ProviderType.anthropic;

  @override
  ProviderCapabilities get caps => const ProviderCapabilities(
    tools: true,
    vision: true,
    streaming: true,
    promptCaching: true,
  );

  Future<Map<String, String>> _headers() async => {
    ..._extraHeaders,
    ...await credentials.headers(_transport.redactor),
    'anthropic-version': apiVersion,
  };

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      _transport.stream(
        cancel: cancel,
        decoder: AnthropicStreamDecoder.new,
        onHttpError: anthropicHttpError,
        build: (attempt, abortTrigger) async {
          final request =
              http.AbortableRequest(
                  'POST',
                  Uri.parse('$_base/messages'),
                  abortTrigger: abortTrigger,
                )
                ..headers.addAll(await _headers())
                ..headers['content-type'] = 'application/json'
                ..headers['accept'] = 'text/event-stream'
                ..body = jsonEncode(buildAnthropicBody(req, options));
          return request;
        },
      );

  @override
  Future<List<ModelInfo>> listModels() async {
    final models = <ModelInfo>[];
    String? after;
    for (var page = 0; page < 20; page++) {
      final url = Uri.parse('$_base/models')
          .replace(queryParameters: {'limit': '1000', 'after_id': ?after});
      final json = await _transport.getJson(
        url,
        await _headers(),
        onHttpError: anthropicHttpError,
      );
      for (final entry in asList(json['data'])) {
        final m = asMap(entry);
        final id = asString(m?['id']);
        if (m == null || id == null) continue;
        final vision = asMap(asMap(m['capabilities'])?['image_input']);
        models.add(
          ModelInfo(
            id: id,
            displayName: asString(m['display_name']),
            contextWindow: asInt(m['max_input_tokens']),
            supportsTools: true,
            supportsVision: vision?['supported'] is bool
                ? vision!['supported']! as bool
                : null,
          ),
        );
      }
      after = asString(json['last_id']);
      if (json['has_more'] != true || after == null) break;
    }
    return models;
  }

  @override
  Future<HealthCheck> test() => runHealthProbe(
    provider: this,
    model: defaultModel,
    clock: settings.clock,
    baseCaps: caps,
  );

  @override
  String toString() => 'AnthropicMessagesAdapter($_base, $defaultModel)';
}
