import 'package:flutter/foundation.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../l10n/l10n.dart';

/// Search services the web integration can use.
enum WebSearchKind {
  /// Brave Search API (key).
  brave('Brave Search', needsKey: true),

  /// Tavily (key).
  tavily('Tavily', needsKey: true),

  /// Own SearXNG instance (base URL, no key).
  searxng('SearXNG (eigene Instanz)', needsKey: false);

  const WebSearchKind(this.label, {required this.needsKey});

  /// Display name (brand names; the own instance has a translated name,
  /// see [labelOf]).
  final String label;

  /// Display name in the app language.
  String labelOf(AppLocalizations l) =>
      this == searxng ? l.webSearchOwnInstance : label;

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
    this.levels = const {},
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
      levels: {
        if (json['levels'] case final Map<Object?, Object?> m)
          for (final e in m.entries)
            // A stored level that is no string stays invalid ('' → D).
            if (e.key is String)
              e.key! as String: e.value is String ? e.value! as String : '',
      },
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

  /// Legacy (before WP154): tools the user wants to confirm every time.
  /// Counts as level D for a tool without an entry in [levels]; written
  /// back unchanged until the user picks a level.
  final Set<String> alwaysConfirm;

  /// The security level (`a`..`d`) the user chose per tool (WP154, ADR 0022);
  /// a tool without entry has its default (`RiskPolicy.defaultLevelOf`).
  /// Kept as text: anything else than `a`..`d` means D (fail-closed).
  final Map<String, String> levels;

  /// The stored level of [tool]: the chosen one, else D for the legacy
  /// "always confirm", else `null` (default).
  String? levelOf(String tool) =>
      levels[tool] ?? (alwaysConfirm.contains(tool) ? 'd' : null);

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
    if (levels.isNotEmpty) 'levels': levels,
    'sensitiveMinimum': ?sensitiveMinimum?.name,
    if (sensitive.isNotEmpty) 'sensitive': sensitive,
  };

  /// A copy with [tool] switched on or off.
  ToolPrefs withEnabled(String tool, {required bool enabled}) => ToolPrefs(
    disabled: enabled ? ({...disabled}..remove(tool)) : {...disabled, tool},
    alwaysConfirm: alwaysConfirm,
    levels: levels,
    sensitiveMinimum: sensitiveMinimum,
    sensitive: sensitive,
  );

  /// A copy where [tool] always needs confirmation (level D) or has its
  /// default again.
  ToolPrefs withConfirm(String tool, {required bool confirm}) =>
      withLevel(tool, confirm ? SecurityLevel.d : null);

  /// A copy with the chosen [level] of [tool] (`null` = default). The
  /// legacy "always confirm" of the tool is dropped: the level replaces it.
  ToolPrefs withLevel(String tool, SecurityLevel? level) => ToolPrefs(
    disabled: disabled,
    alwaysConfirm: {...alwaysConfirm}..remove(tool),
    levels: {
      for (final e in levels.entries)
        if (e.key != tool) e.key: e.value,
      if (level != null) tool: level.name,
    },
    sensitiveMinimum: sensitiveMinimum,
    sensitive: sensitive,
  );

  /// A copy with another [level] for sensitive integrations.
  ToolPrefs withSensitiveMinimum(PrivacyLevel? level) => ToolPrefs(
    disabled: disabled,
    alwaysConfirm: alwaysConfirm,
    levels: levels,
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
    levels: levels,
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
  if (d.taskDefault) 'taskDefault': true,
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
    taskDefault: json['taskDefault'] == true,
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
    this.dailyNotes = defaultDailyNotes,
  });

  /// Decodes [toJson]; malformed parts fall back to the defaults. Stored
  /// daily-note settings stay as they are, also an empty folder (= vault
  /// root); only without any the folder is [defaultDailyFolder].
  factory ObsidianPrefs.fromJson(Map<String, Object?> json) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final daily = json['dailyNotes'];
    if (daily is! Map) {
      return ObsidianPrefs(
        vaultUri: text(json['vaultUri']),
        vaultName: text(json['vaultName']),
      );
    }
    return ObsidianPrefs(
      vaultUri: text(json['vaultUri']),
      vaultName: text(json['vaultName']),
      dailyNotes: DailyNoteSettings(
        folder: daily['folder'] is String ? daily['folder'] as String : '',
        format: text(daily['format']) ?? const DailyNoteSettings().format,
        template: text(daily['template']),
      ),
    );
  }

  /// Daily-note folder until the user chooses one (Obsidian's common
  /// „Journal“; empty = vault root stays possible).
  static const defaultDailyFolder = 'Journal';

  /// Daily-note settings until the user saves own ones.
  static const defaultDailyNotes = DailyNoteSettings(
    folder: defaultDailyFolder,
  );

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
