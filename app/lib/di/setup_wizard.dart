import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'app_settings.dart';
import 'core_providers.dart';
import 'profiles.dart';
import 'providers.dart';
import 'setup_status.dart';
import 'speaker_providers.dart';
import 'voice_settings_providers.dart';
import 'wake_providers.dart';
import 'wake_service.dart';

// State of the setup wizard (WP174): finished flag and current page are
// stored; whether a page is „ticked“ is never stored but derived from the
// live state ([setupFactsProvider]).

/// Whether the setup wizard is finished. Starts from the value read at
/// start ([startupProvider]), so there is no flicker.
final setupWizardDoneProvider = NotifierProvider<SetupWizardDone, bool>(
  SetupWizardDone.new,
);

/// See [setupWizardDoneProvider].
final class SetupWizardDone extends Notifier<bool> {
  @override
  bool build() => ref.watch(startupProvider).setupWizardDone;

  /// Marks the wizard as finished (callers check [SetupFacts.canFinish]).
  Future<void> complete() async {
    state = true;
    await ref
        .read(storageProvider)
        .settings
        .set(AppSettings.setupWizardDone, true);
  }
}

/// Whether the wizard blocks the app: not finished and not in demo mode.
/// Settings pages opened meanwhile lead back to the wizard.
final setupWizardActiveProvider = Provider<bool>(
  (ref) => !ref.watch(setupWizardDoneProvider) && !ref.watch(demoModeProvider),
);

/// The value of [v]; an error counts as unknown even when an earlier value
/// is still there (fail-closed).
T? _known<T>(AsyncValue<T> v) => v.hasError ? null : v.value;

/// The live state of the pages' goals. Errors and loading are `null`
/// (unknown), which counts as not reached where it matters.
final setupFactsProvider = Provider<SetupFacts>((ref) {
  final profiles = _known(ref.watch(profilesProvider));
  final voice = _known(ref.watch(voiceSettingsProvider));
  final states = ref.watch(modelStatesProvider);
  final wake = _known(ref.watch(wakeServiceProvider));
  final speakers = _known(ref.watch(speakerProfilesProvider));

  bool? installed(String id) => switch (states[id]?.phase) {
    ModelPhase.installed => true,
    null || ModelPhase.unknown => null,
    _ => false,
  };

  bool? speech;
  if (voice != null) {
    final parts = [
      installed(voice.sttModel),
      installed(SpeechModelCatalog.sileroVad.id),
    ];
    speech = parts.contains(false)
        ? false
        : parts.contains(null)
        ? null
        : true;
  }
  return SetupFacts(
    providerConfigured: profiles?.profiles.isNotEmpty,
    speechReady: speech,
    wakeReady: wake == null
        ? null
        : wake.enabled && ref.watch(wakeClassifierInstalledProvider),
    speakerEnrolled: speakers?.isNotEmpty,
  );
});

/// The page the wizard is on (stored, so it continues after a restart).
final setupWizardPageProvider = NotifierProvider<SetupWizardPage, SetupPage>(
  SetupWizardPage.new,
);

/// See [setupWizardPageProvider].
final class SetupWizardPage extends Notifier<SetupPage> {
  @override
  SetupPage build() =>
      SetupPage.parse(ref.read(startupProvider).setupWizardPage);

  Future<void> _go(SetupPage page) async {
    state = page;
    await ref
        .read(storageProvider)
        .settings
        .set(AppSettings.setupWizardPage, page.name);
  }

  /// To the next page; `false` when a required page is not met (also when
  /// its state is unknown) or this is the last page.
  Future<bool> advance() async {
    final facts = ref.read(setupFactsProvider);
    final page = facts.effectivePage(state);
    if (!facts.canAdvance(page) || page == SetupPage.done) return false;
    await _go(SetupPage.values[page.index + 1]);
    return true;
  }

  /// To the previous page; `false` on the first.
  Future<bool> back() async {
    final page = ref.read(setupFactsProvider).effectivePage(state);
    if (page == SetupPage.welcome) return false;
    await _go(SetupPage.values[page.index - 1]);
    return true;
  }

  /// Finishes the wizard when every required page is met; otherwise
  /// `false` and nothing changes.
  Future<bool> finish() async {
    if (!ref.read(setupFactsProvider).canFinish) return false;
    await ref.read(setupWizardDoneProvider.notifier).complete();
    return true;
  }
}
