import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/chat_wire.dart';
import '../common/credentials.dart';
import '../common/exchange_tap.dart';
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
    this.wireCodec,
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

  /// Transforms the exchange on the wire (end-to-end encryption, WP62);
  /// `null` = plain JSON.
  final ChatWireCodec? wireCodec;

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
      chatObserved(req, cancel: cancel);

  /// Like [chat]; additionally reports the raw bytes of the exchange to
  /// [observer] when the call ends (before the terminal event is emitted).
  /// Used by the TEE decorator to check receipts against the exact bytes.
  Stream<ChatEvent> chatObserved(
    ChatRequest req, {
    CancelToken? cancel,
    ExchangeObserver? observer,
  }) {
    final tap = observer == null ? null : ExchangeTap(observer);
    ChatWire? wire;
    return _transport.stream(
      cancel: cancel,
      tap: tap,
      checkHead: (headers) => wire?.checkHead(headers),
      openBody: (raw) {
        final w = wire;
        return w is BytesChatWire ? w.openBody(raw) : raw;
      },
      openErrorBody: (headers, raw) {
        final w = wire;
        return w is BytesChatWire ? w.openErrorBody(headers, raw) : raw;
      },
      decoder: () {
        final decoder = OpenAiStreamDecoder(
          label: label,
          emitReasoning: options.emitReasoning,
        );
        final w = wire;
        return w == null ? decoder : WireStreamDecoder(decoder, w);
      },
      onHttpError: _httpError,
      retry: (status, body, attempt) {
        if (attempt == 0 &&
            !body.startsWith(unauthenticatedBodyPrefix) &&
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
        final codec = wireCodec;
        final w = wire = codec == null
            ? null
            : await codec.begin(model: req.model);
        String? text;
        Uint8List? bytes;
        if (w == null) {
          text = jsonEncode(body);
        } else if (w is BytesChatWire) {
          final sealed = w.sealBytes(body);
          bytes = sealed.wire;
          tap?.plainRequest(sealed.plain);
        } else {
          final sealed = w.seal(body);
          text = sealed.wire;
          tap?.plainRequest(sealed.plain);
        }
        final request =
            http.AbortableRequest(
                'POST',
                Uri.parse('$_base/chat/completions'),
                abortTrigger: abortTrigger,
              )
              ..headers.addAll(await _headers())
              ..headers.addAll(w?.headers ?? const {})
              ..headers['content-type'] = 'application/json'
              ..headers['accept'] = 'text/event-stream';
        if (bytes != null) {
          request.bodyBytes = bytes;
        } else {
          request.body = text!;
        }
        return request;
      },
    );
  }

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
              if (options.ownedBy == null || m['owned_by'] == options.ownedBy)
                if (!options.toolsOnly || _supportsTools(m) == true)
                  ModelInfo(
                    id: id,
                    displayName: asString(m['name']),
                    contextWindow:
                        asInt(m['context_length']) ??
                        asInt(m['context_window']),
                    supportsTools: _supportsTools(m),
                  ),
    ];
  }

  static bool? _supportsTools(Map<String, Object?> model) {
    final params = model['supported_parameters'];
    if (params is List<Object?>) return params.contains('tools');
    final features = model['supported_features']; // NEAR AI
    return features is List<Object?> ? features.contains('tools') : null;
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
