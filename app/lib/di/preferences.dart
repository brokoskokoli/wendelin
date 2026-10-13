import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';
import 'preference_models.dart';
import 'providers.dart';

// User preferences that change at runtime. Each notifier starts from the
// settings read at start ([startupProvider]) and stores every change.

SettingsRepository _settings(Ref ref) => ref.read(storageProvider).settings;

/// Whether the onboarding is done.
final onboardingDoneProvider = NotifierProvider<OnboardingDone, bool>(
  OnboardingDone.new,
);

/// Onboarding state.
final class OnboardingDone extends Notifier<bool> {
  @override
  bool build() => ref.watch(startupProvider).onboardingDone;

  /// Marks the onboarding as done.
  Future<void> complete() async {
    state = true;
    await _settings(ref).set(AppSettings.onboardingDone, true);
  }
}

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

/// Deletes audit entries and conversations older than [days].
Future<void> purgeExpired(WendelinStorage storage, int days) async {
  final age = Duration(days: days);
  await storage.audit.purgeOlderThan(age);
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

  /// Adds [list] or replaces the one with the same id.
  Future<void> save(ListDefinition list) => _store([
    for (final l in state)
      if (l.id != list.id) l,
    list,
  ]);

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
    if (registry.integrations.any((i) => i.id == 'lists')) {
      await registry.refresh('lists');
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
