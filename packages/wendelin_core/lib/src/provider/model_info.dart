import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A model offered by a provider (from `LlmProvider.listModels`).
@immutable
final class ModelInfo {
  /// Creates model info; unknown properties stay `null`.
  const ModelInfo({
    required this.id,
    String? displayName,
    this.contextWindow,
    this.supportsTools,
    this.supportsVision,
  }) : displayName = displayName ?? id;

  /// Provider model id used in `ChatRequest.model`.
  final String id;

  /// Name for the UI (defaults to [id]).
  final String displayName;

  /// Context window in tokens, if known.
  final int? contextWindow;

  /// Whether tool calling works, if known.
  final bool? supportsTools;

  /// Whether image input works, if known.
  final bool? supportsVision;

  @override
  bool operator ==(Object other) =>
      other is ModelInfo &&
      other.id == id &&
      other.displayName == displayName &&
      other.contextWindow == contextWindow &&
      other.supportsTools == supportsTools &&
      other.supportsVision == supportsVision;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    contextWindow,
    supportsTools,
    supportsVision,
  );

  @override
  String toString() => 'ModelInfo($id)';
}

/// Result of `LlmProvider.test()` for the setup dialog.
@immutable
final class HealthCheck {
  /// Creates a health check result.
  HealthCheck({
    required this.ok,
    required this.latency,
    required this.message,
    List<ModelInfo>? models,
  }) : models = models == null ? null : List.unmodifiable(models);

  /// Whether the provider is usable.
  final bool ok;

  /// Round-trip time of the test request.
  final Duration latency;

  /// Short, secret-free explanation for the user.
  final String message;

  /// Models found during the check, if any were loaded.
  final List<ModelInfo>? models;

  @override
  bool operator ==(Object other) =>
      other is HealthCheck &&
      other.ok == ok &&
      other.latency == latency &&
      other.message == message &&
      const ListEquality<ModelInfo>().equals(other.models, models);

  @override
  int get hashCode => Object.hash(
    ok,
    latency,
    message,
    models == null ? null : const ListEquality<ModelInfo>().hash(models),
  );

  @override
  String toString() => 'HealthCheck(ok: $ok, $latency, $message)';
}
