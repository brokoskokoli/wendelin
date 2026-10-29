import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../l10n/l10n.dart';
import '../platform/screen_protection.dart';
import 'app_settings.dart';
import 'preference_models.dart';
import 'providers.dart';

// User preferences that change at runtime. Each notifier starts from the
// settings read at start ([startupProvider]) and stores every change.

SettingsRepository _settings(Ref ref) => ref.read(storageProvider).settings;

/// Preferred language (`de`, `fr`, `en`).
final languageProvider = NotifierProvider<LanguagePref, String>(
  LanguagePref.new,
);

/// Language preference.
final class LanguagePref extends Notifier<String> {
  @override
  String build() => ref.watch(startupProvider).language;

  /// Stores [code].
  Future<void> set(String code) async {
    state = code;
    await _settings(ref).set(AppSettings.language, code);
  }
}

/// Language of the app UI (`system`, `de`, `en`, `fr`), independent of
/// [languageProvider] (speech and prompts).
final uiLanguageProvider = NotifierProvider<UiLanguagePref, String>(
  UiLanguagePref.new,
);

/// UI language preference.
final class UiLanguagePref extends Notifier<String> {
  @override
  String build() => ref.watch(startupProvider).uiLanguage;

  /// Stores [code] (`system` or a supported language code).
  Future<void> set(String code) async {
    state = code;
    await _settings(ref).set(AppSettings.uiLanguage, code);
  }
}

/// The UI texts in the current app language, for places without a
/// `BuildContext` (hints the agent adds to the conversation). Evaluated at
/// call time: a changed language applies to the next hint.
AppLocalizations uiTexts(Ref ref) {
  var code = uiLanguageSystem;
  try {
    code = ref.read(uiLanguageProvider);
  } on Object {
    // No settings yet (plain provider tests): follow the system.
  }
  final locale =
      uiLocaleFor(code) ??
      resolveUiLocale(
        WidgetsBinding.instance.platformDispatcher.locales,
        AppLocalizations.supportedLocales,
      );
  return lookupAppLocalizations(locale);
}

/// User name and persona addition.
final assistantPrefsProvider =
    NotifierProvider<AssistantPrefsNotifier, AssistantPrefs>(
      AssistantPrefsNotifier.new,
    );

/// Assistant preferences.
final class AssistantPrefsNotifier extends Notifier<AssistantPrefs> {
  @override
  AssistantPrefs build() => ref.watch(startupProvider).assistant;

  /// Stores [prefs]; blank texts are removed.
  Future<void> set(AssistantPrefs prefs) async {
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final next = AssistantPrefs(
      userName: clean(prefs.userName),
      persona: clean(prefs.persona),
    );
    state = next;
    final s = _settings(ref);
    for (final (key, value) in [
      (AppSettings.userName, next.userName),
      (AppSettings.persona, next.persona),
    ]) {
      value == null ? await s.remove(key) : await s.set(key, value);
    }
  }
}

/// Retention of audit log and conversations in days.
final retentionDaysProvider = NotifierProvider<RetentionDays, int>(
  RetentionDays.new,
);

/// Retention setting.
final class RetentionDays extends Notifier<int> {
  /// Offered choices.
  static const choices = [7, 30, 90, 365];

  @override
  int build() => ref.watch(startupProvider).retentionDays;

  /// Stores [days] and deletes what is older right away.
  Future<void> set(int days) async {
    state = days;
    await _settings(ref).set(AppSettings.retentionDays, days);
    await purgeExpired(ref.read(storageProvider), days);
  }
}

/// Deletes audit entries, verification log and conversations older than [days].
Future<void> purgeExpired(WendelinStorage storage, int days) async {
  final age = Duration(days: days);
  await storage.audit.purgeOlderThan(age);
  await storage.attestations.purgeOlderThan(age);
  await storage.conversations.purgeOlderThan(age);
}

/// Tool switches, confirmations and the level for sensitive integrations.
final toolPrefsProvider = NotifierProvider<ToolPrefsNotifier, ToolPrefs>(
  ToolPrefsNotifier.new,
);

/// Tool preferences.
final class ToolPrefsNotifier extends Notifier<ToolPrefs> {
  @override
  ToolPrefs build() => ref.watch(startupProvider).toolPrefs;

  /// Stores [prefs].
  Future<void> set(ToolPrefs prefs) async {
    state = prefs;
    await _settings(ref).set(AppSettings.toolPrefs, prefs);
  }
}

/// Configured web search service; `null` = none (only `web__fetch`).
final webSearchConfigProvider =
    NotifierProvider<WebSearchConfigNotifier, WebSearchConfig?>(
      WebSearchConfigNotifier.new,
    );

/// Web search setting.
final class WebSearchConfigNotifier extends Notifier<WebSearchConfig?> {
  @override
  WebSearchConfig? build() => ref.watch(startupProvider).webSearch;

  /// Stores [config]; with [apiKey] the key goes straight into the
  /// `SecretStore` (never into settings or state). `null` removes the
  /// service and its keys.
  Future<void> set(WebSearchConfig? config, {String? apiKey}) async {
    final secrets = ref.read(secretStoreProvider);
    final settings = _settings(ref);
    if (config == null) {
      for (final kind in WebSearchKind.values) {
        await secrets.delete(kind.secretRef);
      }
      await settings.remove(AppSettings.webSearch);
    } else {
      // Keys of services no longer in use are removed.
      for (final kind in WebSearchKind.values) {
        if (kind != config.kind) await secrets.delete(kind.secretRef);
      }
      if (apiKey != null && apiKey.trim().isNotEmpty) {
        await secrets.write(config.kind.secretRef, apiKey.trim());
      }
      await settings.set(AppSettings.webSearch, config);
    }
    state = config;
  }

  /// Whether a key is stored for [kind].
  Future<bool> hasKey(WebSearchKind kind) async {
    final key = await ref.read(secretStoreProvider).read(kind.secretRef);
    return key != null && key.isNotEmpty;
  }
}

/// The user's lists (K6).
final listDefinitionsProvider =
    NotifierProvider<ListDefinitionsNotifier, List<ListDefinition>>(
      ListDefinitionsNotifier.new,
    );

/// List definitions in the settings.
final class ListDefinitionsNotifier extends Notifier<List<ListDefinition>> {
  @override
  List<ListDefinition> build() => ref.watch(startupProvider).lists;

  /// Adds [list] or replaces the one with the same id. At most one list is
  /// the default task list: setting it clears the flag on the others.
  Future<void> save(ListDefinition list) => _store([
    for (final l in state)
      if (l.id != list.id) list.taskDefault ? _asPlain(l) : l,
    list,
  ]);

  static ListDefinition _asPlain(ListDefinition l) => !l.taskDefault
      ? l
      : ListDefinition(
          id: l.id,
          name: l.name,
          target: l.target,
          aliases: l.aliases,
          section: l.section,
        );

  /// Removes the list [id].
  Future<void> remove(String id) => _store([
    for (final l in state)
      if (l.id != id) l,
  ]);

  Future<void> _store(List<ListDefinition> lists) async {
    state = List.unmodifiable(lists);
    await _settings(ref).set(AppSettings.lists, lists);
    // The integration needs at least one list (setup step).
    final registry = ref.read(toolRegistryProvider);
    for (final id in const ['lists', 'tasks']) {
      if (registry.integrations.any((i) => i.id == id)) {
        await registry.refresh(id);
      }
    }
  }
}

/// Obsidian vault and daily notes.
final obsidianPrefsProvider =
    NotifierProvider<ObsidianPrefsNotifier, ObsidianPrefs>(
      ObsidianPrefsNotifier.new,
    );

/// Obsidian settings.
final class ObsidianPrefsNotifier extends Notifier<ObsidianPrefs> {
  @override
  ObsidianPrefs build() => ref.watch(startupProvider).obsidian;

  /// Stores [prefs]. The caller re-checks the setup step of the
  /// integration (`ToolRegistry.refresh('obsidian')`); the registry is not
  /// read here because the platform ports read this provider.
  Future<void> set(ObsidianPrefs prefs) async {
    state = prefs;
    await _settings(ref).set(AppSettings.obsidian, prefs);
  }
}

/// Window protection of the main app (overridden in tests).
final screenProtectionProvider = Provider<ScreenProtection>(
  (ref) => const ScreenProtection(),
);

/// „Bildschirminhalt schützen“ (Einstellungen → Datenschutz, default off).
final secureScreenProvider = NotifierProvider<SecureScreen, bool>(
  SecureScreen.new,
);

/// „Einfache Befehle sofort ausführen“ (Einstellungen → Home Assistant,
/// default on, WP135 D).
final haFastPathProvider = NotifierProvider<HaFastPathSetting, bool>(
  HaFastPathSetting.new,
);

/// Fast path setting for Home Assistant commands.
final class HaFastPathSetting extends Notifier<bool> {
  @override
  bool build() => ref.watch(startupProvider).haFastPath;

  /// Stores [on]; the next request uses it.
  Future<void> set({required bool on}) async {
    state = on;
    await _settings(ref).set(AppSettings.haFastPath, on);
  }
}

/// „Navigations-App“ (Einstellungen → Google Maps / Waze, WP164 B): the app
/// `maps__navigate` uses without an `app` argument; `null` = default.
final navigationAppProvider =
    NotifierProvider<NavigationAppSetting, NavigationApp?>(
      NavigationAppSetting.new,
    );

/// Setting „Navigations-App“.
final class NavigationAppSetting extends Notifier<NavigationApp?> {
  @override
  NavigationApp? build() =>
      NavigationApp.parse(ref.watch(startupProvider).navigationApp);

  /// Stores [app] (`null` = default); the next request uses it.
  Future<void> set(NavigationApp? app) async {
    state = app;
    final settings = _settings(ref);
    if (app == null) {
      await settings.remove(AppSettings.navigationApp);
    } else {
      await settings.set(AppSettings.navigationApp, app.id);
    }
  }
}

/// Screen protection setting of the main app.
final class SecureScreen extends Notifier<bool> {
  @override
  bool build() => ref.watch(startupProvider).secureScreen;

  /// Stores [secure] and applies it right away.
  Future<void> set({required bool secure}) async {
    state = secure;
    await _settings(ref).set(AppSettings.secureScreen, secure);
    await ref.read(screenProtectionProvider).apply(secure: secure);
  }
}
