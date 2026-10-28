import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../l10n/gen/app_localizations.dart';
import '../platform/wake/wake_platform.dart';
import '../platform/wake/wake_stage2_gap.dart';
import 'core_providers.dart';
import 'preferences.dart';
import 'voice_settings_providers.dart';
import 'wake_providers.dart';

// The wake word service switch (WP50): the settings live in the database;
// every change is mirrored to Kotlin, which starts or stops the service.
// The settings page comes with WP50 part b.

/// Setting „Wake Word an“ (default off).
final wakeEnabledKey = SettingKey.boolean('wake.enabled', defaultValue: false);

/// Setting „Bedingung“: `charging` (default) or `always`.
final wakeConditionKey = SettingKey.string(
  'wake.condition',
  defaultValue: 'charging',
);

/// Switch and condition of the wake word service.
@immutable
final class WakeServiceSettings {
  /// Creates the settings.
  const WakeServiceSettings({
    this.enabled = false,
    this.condition = WakeCondition.charging,
  });

  /// The service listens (under [condition]).
  final bool enabled;

  /// When it listens.
  final WakeCondition condition;
}

/// Reads and stores the switch, mirrors it to the service.
final wakeServiceProvider =
    AsyncNotifierProvider<WakeServiceNotifier, WakeServiceSettings>(
      WakeServiceNotifier.new,
    );

/// See [wakeServiceProvider].
final class WakeServiceNotifier extends AsyncNotifier<WakeServiceSettings> {
  @override
  Future<WakeServiceSettings> build() async {
    final settings = ref.read(storageProvider).settings;
    // „Nachprüfung“ is part of what the service needs to know.
    ref.listen(wakeVerifyProvider, (_, _) => unawaited(push()));
    // WP129: the choice of the detection goes to the service as well.
    ref.listen(wakeDetectorProvider, (_, _) => unawaited(push()));
    // WP156: the notification speaks the app language; a changed language
    // goes to the service as well.
    try {
      ref.listen(uiLanguageProvider, (_, _) => unawaited(push()));
    } on Object catch (e) {
      // No settings yet (plain provider tests): the texts follow the system.
      debugPrint('wake-texts listen=skipped type=${e.runtimeType}');
    }
    // WP171: what stage 2 needs changed (recognition model installed or
    // removed, voice enrolled or deleted): the engine checks the gap again.
    ref
      ..listen(
        modelStatesProvider.select(wakeStage2RecognizerInstalled),
        (_, _) => unawaited(ref.read(wakePlatformProvider).recheckStage2()),
      )
      ..listen(
        wakeSpeakersProvider,
        (_, _) => unawaited(ref.read(wakePlatformProvider).recheckStage2()),
      );
    return WakeServiceSettings(
      enabled: await settings.get(wakeEnabledKey) ?? false,
      condition: WakeCondition.parse(await settings.get(wakeConditionKey)),
    );
  }

  /// Sends the settings to the service (also at every start of the app,
  /// the assistant role may have changed).
  Future<void> push() async {
    final s = await future;
    if (!ref.mounted) return;
    final verify = await ref.read(wakeVerifyProvider.future);
    if (!ref.mounted) return;
    final detector = await ref.read(wakeDetectorProvider.future);
    if (!ref.mounted) return;
    final platform = ref.read(wakePlatformProvider);
    // Before `configure`: that call may start the service, which needs them.
    try {
      await platform.setTexts(wakeNotificationTexts(uiTexts(ref)));
    } on Object catch (e) {
      // No binding for the system language (plain provider tests): Kotlin
      // keeps the texts it has, or German.
      debugPrint('wake-texts result=error type=${e.runtimeType}');
    }
    if (!ref.mounted) return;
    await platform.configure(
      enabled: s.enabled,
      condition: s.condition,
      verify: verify,
      detector: detector.name,
    );
  }

  /// Start of the app: takes over „Aus“ from the notification (Kotlin
  /// switched the service off), otherwise sends the settings again (the
  /// assistant role may have changed).
  Future<void> sync() async {
    final status = await ref.read(wakePlatformProvider).status();
    // The provider may be gone after the await (screen or test ended).
    if (!ref.mounted) return;
    if (!await adoptStatus(status)) await push();
  }

  /// Takes over an „Aus“ that Kotlin reports (`offByUser`, notification button) so the
  /// next [push] does not switch the service on again. `true` if the
  /// switch was changed.
  Future<bool> adoptStatus(WakeServiceStatus status) async {
    final s = await future;
    if (!ref.mounted || !status.offByUser || !s.enabled) return false;
    state = AsyncData(WakeServiceSettings(condition: s.condition));
    await ref.read(storageProvider).settings.set(wakeEnabledKey, false);
    return true;
  }

  /// Switches the service on or off. Without a learned voice it cannot be
  /// switched on (`false`, WP50 Nachtrag) when the templates path is the one
  /// that listens; the installed classifier model needs no voice (WP140).
  Future<bool> setEnabled({required bool enabled}) async {
    if (enabled &&
        ref.read(wakeNeedsVoiceProvider) &&
        (await ref.read(wakeSpeakersProvider.future)).isEmpty) {
      return false;
    }
    if (!ref.mounted) return false;
    final condition = (await future).condition;
    if (!ref.mounted) return false;
    state = AsyncData(
      WakeServiceSettings(enabled: enabled, condition: condition),
    );
    await ref.read(storageProvider).settings.set(wakeEnabledKey, enabled);
    await push();
    return true;
  }

  /// Chooses when it listens.
  Future<void> setCondition(WakeCondition condition) async {
    final enabled = (await future).enabled;
    if (!ref.mounted) return;
    state = AsyncData(
      WakeServiceSettings(enabled: enabled, condition: condition),
    );
    await ref
        .read(storageProvider)
        .settings
        .set(wakeConditionKey, condition.name);
    await push();
  }
}

/// The texts of the service notification (WP156), keys as in
/// `WakeNotifications.kt`. `{time}` and `{reason}` are filled by Kotlin.
Map<String, String> wakeNotificationTexts(AppLocalizations t) => {
  'channelDesc': t.wakeNotifChannelDesc,
  'listeningTitle': t.wakeNotifListeningTitle,
  'listeningText': t.wakeNotifListeningText,
  'pause': t.wakeNotifPause,
  'off': t.wakeNotifOff,
  'pausedTitle': t.wakeNotifPausedTitle,
  'pausedText': t.wakeNotifPausedText('{time}'),
  'resume': t.wakeNotifResume,
  'reenableTitle': t.wakeNotifReenableTitle,
  'reenableAction': t.wakeNotifReenableAction,
  'noRole': t.wakeNotifNoRole,
  'gapText': t.wakeNotifGapText,
  'gapAction': t.wakeNotifGapAction,
  'gapNoSeqText': t.wakeNotifGapNoSeqText,
  'gapNoSeqAction': t.wakeNotifGapNoSeqAction,
  'ended': t.wakeNotifEnded('{reason}'),
};
