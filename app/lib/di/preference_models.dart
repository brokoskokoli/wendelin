import 'package:flutter/foundation.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Search services the web integration can use.
enum WebSearchKind {
  /// Brave Search API (key).
  brave('Brave Search', needsKey: true),

  /// Tavily (key).
  tavily('Tavily', needsKey: true),

  /// Own SearXNG instance (base URL, no key).
  searxng('SearXNG (eigene Instanz)', needsKey: false);

  const WebSearchKind(this.label, {required this.needsKey});

  /// Display name.
  final String label;

  /// Whether an API key is required.
  final bool needsKey;

  /// Key of the API key in the `SecretStore`.
  String get secretRef => 'web.search.$name.apiKey';
}

/// The configured search service (no secrets; the key is in the
/// `SecretStore` under [WebSearchKind.secretRef]).
@immutable
final class WebSearchConfig {
  /// Creates a configuration.
  const WebSearchConfig(this.kind, {this.baseUrl});

  /// Decodes [toJson]; throws [FormatException].
  factory WebSearchConfig.fromJson(Map<String, Object?> json) {
    final kind = WebSearchKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (kind == null) throw const FormatException('web.search: Art fehlt');
    final url = json['baseUrl'];
    if (url != null && url is! String) {
      throw const FormatException('web.search: baseUrl ist kein Text');
    }
    return WebSearchConfig(kind, baseUrl: url as String?);
  }

  /// Service.
  final WebSearchKind kind;

  /// Base URL (SearXNG).
  final String? baseUrl;

  /// JSON for the settings.
  Map<String, Object?> toJson() => {'kind': kind.name, 'baseUrl': ?baseUrl};

  @override
  bool operator ==(Object other) =>
      other is WebSearchConfig &&
      other.kind == kind &&
      other.baseUrl == baseUrl;

  @override
  int get hashCode => Object.hash(kind, baseUrl);
}

/// The user's choices per tool and for sensitive integrations.
@immutable
final class ToolPrefs {
  /// Creates the preferences.
  const ToolPrefs({
    this.disabled = const {},
    this.alwaysConfirm = const {},
    this.sensitiveMinimum,
    this.sensitive = const {},
  });

  /// Decodes [toJson]; unknown or malformed parts are ignored.
  factory ToolPrefs.fromJson(Map<String, Object?> json) {
    Set<String> names(Object? v) => v is List
        ? {
            for (final e in v)
              if (e is String) e,
          }
        : const {};
    final level = PrivacyLevel.values
        .where((l) => l.name == json['sensitiveMinimum'])
        .firstOrNull;
    final marks = json['sensitive'];
    return ToolPrefs(
      disabled: names(json['disabled']),
      alwaysConfirm: names(json['alwaysConfirm']),
      sensitiveMinimum: level,
      sensitive: {
        if (marks is Map)
          for (final e in marks.entries)
            if (e.key is String && e.value is bool)
              e.key as String: e.value as bool,
      },
    );
  }

  /// Tools switched off (not sent to the model).
  final Set<String> disabled;

  /// `read`/`write` tools the user wants to confirm every time (risk levels
  /// can only be made stricter, K8 b).
  final Set<String> alwaysConfirm;

  /// Tools of sensitive integrations only go to providers at least this
  /// private; `null` = no restriction.
  final PrivacyLevel? sensitiveMinimum;

  /// The user's „sensibel“ marks per integration id (overrides the
  /// integration's default).
  final Map<String, bool> sensitive;

  /// JSON for the settings.
  Map<String, Object?> toJson() => {
    'disabled': disabled.toList()..sort(),
    'alwaysConfirm': alwaysConfirm.toList()..sort(),
    'sensitiveMinimum': ?sensitiveMinimum?.name,
    if (sensitive.isNotEmpty) 'sensitive': sensitive,
  };

  /// A copy with [tool] switched on or off.
  ToolPrefs withEnabled(String tool, {required bool enabled}) => ToolPrefs(
    disabled: enabled ? ({...disabled}..remove(tool)) : {...disabled, tool},
    alwaysConfirm: alwaysConfirm,
    sensitiveMinimum: sensitiveMinimum,
    sensitive: sensitive,
  );

  /// A copy where [tool] always needs confirmation (or not).
  ToolPrefs withConfirm(String tool, {required bool confirm}) => ToolPrefs(
    disabled: disabled,
    alwaysConfirm: confirm
        ? {...alwaysConfirm, tool}
        : ({...alwaysConfirm}..remove(tool)),
    sensitiveMinimum: sensitiveMinimum,
    sensitive: sensitive,
  );

  /// A copy with another [level] for sensitive integrations.
  ToolPrefs withSensitiveMinimum(PrivacyLevel? level) => ToolPrefs(
    disabled: disabled,
    alwaysConfirm: alwaysConfirm,
    sensitiveMinimum: level,
    sensitive: sensitive,
  );

  /// A copy with integration [id] marked as sensitive or not; [byDefault]
  /// is the integration's own value (no override is stored for it).
  ToolPrefs withSensitive(
    String id, {
    required bool sensitive,
    required bool byDefault,
  }) => ToolPrefs(
    disabled: disabled,
    alwaysConfirm: alwaysConfirm,
    sensitiveMinimum: sensitiveMinimum,
    sensitive: {
      for (final e in this.sensitive.entries)
        if (e.key != id) e.key: e.value,
      if (sensitive != byDefault) id: sensitive,
    },
  );
}

/// Name of the user and persona addition for the system prompt.
@immutable
final class AssistantPrefs {
  /// Creates the preferences.
  const AssistantPrefs({this.userName, this.persona});

  /// How the assistant addresses the user.
  final String? userName;

  /// Free text added to the system prompt.
  final String? persona;
}

/// JSON of a [ListDefinition] (settings).
Map<String, Object?> listDefinitionToJson(ListDefinition d) => {
  'id': d.id,
  'name': d.name,
  'target': d.target,
  if (d.aliases.isNotEmpty) 'aliases': d.aliases,
  'section': ?d.section,
};

/// A [ListDefinition] from [listDefinitionToJson]; throws [FormatException].
ListDefinition listDefinitionFromJson(Object? json) {
  if (json is! Map) throw const FormatException('Liste: Objekt erwartet');
  final id = json['id'], name = json['name'], target = json['target'];
  final aliases = json['aliases'] ?? const <Object?>[];
  final section = json['section'];
  if (id is! String ||
      name is! String ||
      target is! String ||
      aliases is! List ||
      (section != null && section is! String)) {
    throw const FormatException('Liste: Felder fehlen oder falsch');
  }
  return ListDefinition(
    id: id,
    name: name,
    target: target,
    aliases: [
      for (final a in aliases)
        if (a is String) a,
    ],
    section: section as String?,
  );
}

/// The user's Obsidian settings: chosen vault (SAF tree URI with persisted
/// grant, display name) and daily notes. No secrets.
@immutable
final class ObsidianPrefs {
  /// Creates the settings.
  const ObsidianPrefs({
    this.vaultUri,
    this.vaultName,
    this.dailyNotes = const DailyNoteSettings(),
  });

  /// Decodes [toJson]; malformed parts fall back to the defaults.
  factory ObsidianPrefs.fromJson(Map<String, Object?> json) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final daily = json['dailyNotes'];
    final d = daily is Map ? daily : const <Object?, Object?>{};
    return ObsidianPrefs(
      vaultUri: text(json['vaultUri']),
      vaultName: text(json['vaultName']),
      dailyNotes: DailyNoteSettings(
        folder: text(d['folder']) ?? '',
        format: text(d['format']) ?? const DailyNoteSettings().format,
        template: text(d['template']),
      ),
    );
  }

  /// Tree URI of the vault folder; `null` = none chosen.
  final String? vaultUri;

  /// Folder name of the vault (as Obsidian names the vault).
  final String? vaultName;

  /// Daily-note folder, date format and template.
  final DailyNoteSettings dailyNotes;

  /// Whether a vault is chosen.
  bool get hasVault => vaultUri != null;

  /// JSON for the settings.
  Map<String, Object?> toJson() => {
    'vaultUri': ?vaultUri,
    'vaultName': ?vaultName,
    'dailyNotes': {
      'folder': dailyNotes.folder,
      'format': dailyNotes.format,
      'template': ?dailyNotes.template,
    },
  };

  /// A copy with another vault (`null` removes it).
  ObsidianPrefs withVault(String? uri, String? name) =>
      ObsidianPrefs(vaultUri: uri, vaultName: name, dailyNotes: dailyNotes);

  /// A copy with other daily-note settings.
  ObsidianPrefs withDailyNotes(DailyNoteSettings daily) => ObsidianPrefs(
    vaultUri: vaultUri,
    vaultName: vaultName,
    dailyNotes: daily,
  );

  @override
  bool operator ==(Object other) =>
      other is ObsidianPrefs &&
      other.vaultUri == vaultUri &&
      other.vaultName == vaultName &&
      other.dailyNotes == dailyNotes;

  @override
  int get hashCode => Object.hash(vaultUri, vaultName, dailyNotes);
}
