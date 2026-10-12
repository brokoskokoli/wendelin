import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../util/json_read.dart';
import 'auth_method.dart';
import 'privacy_level.dart';
import 'provider_type.dart';

/// A user-configured provider ("Claude API", "Ollama Homeserver").
///
/// Contains no secrets: credentials are referenced through [authMethod]
/// (`secretRef`) and live in the `SecretStore`. Safe to persist as JSON.
@immutable
final class ProviderProfile {
  /// Creates a profile.
  ProviderProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.defaultModel,
    required this.privacy,
    required this.authMethod,
    this.baseUrl,
    this.budgetMonthly,
    this.warnThreshold,
    Map<String, String> extraHeaders = const {},
  }) : extraHeaders = Map.unmodifiable(extraHeaders);

  /// Decodes a profile written by [toJson]; throws [FormatException].
  factory ProviderProfile.fromJson(Map<String, Object?> json) {
    const c = 'ProviderProfile';
    return ProviderProfile(
      id: readField(json, 'id', c),
      name: readField(json, 'name', c),
      type: readEnum(json, 'type', ProviderType.values, c),
      baseUrl: readOptional<String>(json, 'baseUrl', c),
      defaultModel: readField(json, 'defaultModel', c),
      privacy: readEnum(json, 'privacy', PrivacyLevel.values, c),
      authMethod: AuthMethod.fromJson(readMap(json, 'authMethod', c)),
      budgetMonthly: readOptional<int>(json, 'budgetMonthly', c),
      warnThreshold: readOptional<num>(json, 'warnThreshold', c)?.toDouble(),
      extraHeaders: json['extraHeaders'] == null
          ? const {}
          : readStringMap(json, 'extraHeaders', c),
    );
  }

  /// Stable id.
  final String id;

  /// Display name.
  final String name;

  /// API family / adapter.
  final ProviderType type;

  /// Base URL; `null` = adapter default (e.g. `https://api.anthropic.com`).
  final String? baseUrl;

  /// Model used unless routing picks another.
  final String defaultModel;

  /// Data-protection level of this provider.
  final PrivacyLevel privacy;

  /// How to authenticate (references secrets, never contains them).
  final AuthMethod authMethod;

  /// Monthly budget in **micro-USD** (1 USD = 1 000 000), matching
  /// `costMicros` elsewhere; `null` = unlimited.
  final int? budgetMonthly;

  /// Fraction of [budgetMonthly] (0.0–1.0) at which to warn; `null` = none.
  final double? warnThreshold;

  /// Additional *non-secret* headers (secret headers belong in
  /// [CustomHeadersAuth]).
  final Map<String, String> extraHeaders;

  /// Encodes the profile as JSON (no secrets).
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    if (baseUrl != null) 'baseUrl': baseUrl,
    'defaultModel': defaultModel,
    'privacy': privacy.name,
    'authMethod': authMethod.toJson(),
    if (budgetMonthly != null) 'budgetMonthly': budgetMonthly,
    if (warnThreshold != null) 'warnThreshold': warnThreshold,
    if (extraHeaders.isNotEmpty) 'extraHeaders': extraHeaders,
  };

  /// Returns a copy with the given fields replaced. Nullable fields cannot be
  /// reset to `null` through this method; construct a new profile instead.
  ProviderProfile copyWith({
    String? id,
    String? name,
    ProviderType? type,
    String? baseUrl,
    String? defaultModel,
    PrivacyLevel? privacy,
    AuthMethod? authMethod,
    int? budgetMonthly,
    double? warnThreshold,
    Map<String, String>? extraHeaders,
  }) => ProviderProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    baseUrl: baseUrl ?? this.baseUrl,
    defaultModel: defaultModel ?? this.defaultModel,
    privacy: privacy ?? this.privacy,
    authMethod: authMethod ?? this.authMethod,
    budgetMonthly: budgetMonthly ?? this.budgetMonthly,
    warnThreshold: warnThreshold ?? this.warnThreshold,
    extraHeaders: extraHeaders ?? this.extraHeaders,
  );

  @override
  bool operator ==(Object other) =>
      other is ProviderProfile &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.baseUrl == baseUrl &&
      other.defaultModel == defaultModel &&
      other.privacy == privacy &&
      other.authMethod == authMethod &&
      other.budgetMonthly == budgetMonthly &&
      other.warnThreshold == warnThreshold &&
      const MapEquality<String, String>().equals(
        other.extraHeaders,
        extraHeaders,
      );

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    baseUrl,
    defaultModel,
    privacy,
    authMethod,
    budgetMonthly,
    warnThreshold,
    const MapEquality<String, String>().hash(extraHeaders),
  );

  @override
  String toString() => 'ProviderProfile($id, ${type.name}, ${privacy.name})';
}
