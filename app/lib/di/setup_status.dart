import 'package:flutter/foundation.dart';

/// Pages of the setup wizard (WP174), in order.
enum SetupPage {
  /// Welcome and language.
  welcome,

  /// First AI provider (required).
  provider,

  /// Speech recognition and voice activity model (required).
  speech,

  /// Wake word (optional).
  wakeWord,

  /// Integrations (optional).
  integrations,

  /// Speaker recognition (optional).
  personalization,

  /// Closing page.
  done;

  /// Whether the wizard cannot go on before the page is fulfilled.
  bool get isRequired => this == provider || this == speech;

  /// The page with the stored [name], or [welcome] for unknown values.
  static SetupPage parse(String? name) => SetupPage.values.firstWhere(
    (p) => p.name == name,
    orElse: () => SetupPage.welcome,
  );
}

/// Whether the page's goal is reached, derived from the live state.
enum PageState {
  /// Reached.
  met,

  /// Known not to be reached.
  unmet,

  /// Not known yet or unreadable. Counts as not reached where it matters.
  unknown,

  /// The page has no state of its own (welcome, integrations, done).
  none,
}

/// What the live state says; `null` = not known (loading or an error).
/// „Done“ is never stored, it is derived from these facts each time.
@immutable
final class SetupFacts {
  /// Creates the facts; everything unknown by default.
  const SetupFacts({
    this.providerConfigured,
    this.speechReady,
    this.wakeReady,
    this.speakerEnrolled,
  });

  /// At least one provider profile exists.
  final bool? providerConfigured;

  /// The chosen recognition model and Silero VAD are installed.
  final bool? speechReady;

  /// The wake word is switched on and its model is installed.
  final bool? wakeReady;

  /// At least one person is enrolled for speaker recognition.
  final bool? speakerEnrolled;

  /// State of [page].
  PageState stateOf(SetupPage page) {
    final fact = switch (page) {
      SetupPage.provider => providerConfigured,
      SetupPage.speech => speechReady,
      SetupPage.wakeWord => wakeReady,
      SetupPage.personalization => speakerEnrolled,
      _ => 0,
    };
    return switch (fact) {
      true => PageState.met,
      false => PageState.unmet,
      null => PageState.unknown,
      _ => PageState.none,
    };
  }

  /// Whether the wizard may leave [page] forward. Required pages need the
  /// state `met`; unknown counts as not met (fail-closed).
  bool canAdvance(SetupPage page) =>
      !page.isRequired || stateOf(page) == PageState.met;

  /// Whether the wizard may finish: every required page is met.
  bool get canFinish =>
      SetupPage.values.where((p) => p.isRequired).every(canAdvance);

  /// The page to show for the stored [page]: never behind a required page
  /// that is known to be unmet (e.g. the provider was deleted meanwhile).
  /// Unknown does not move the page back, so a resume does not jump while
  /// the state still loads; leaving a page still needs [canAdvance].
  SetupPage effectivePage(SetupPage page) {
    for (final p in SetupPage.values) {
      if (p.index >= page.index) break;
      if (p.isRequired && stateOf(p) == PageState.unmet) return p;
    }
    return page;
  }
}
