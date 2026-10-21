import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/wake/wake_platform.dart';
import 'core_providers.dart';
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
    await ref
        .read(wakePlatformProvider)
        .configure(enabled: s.enabled, condition: s.condition, verify: verify);
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
  /// switched on (`false`, WP50 Nachtrag).
  Future<bool> setEnabled({required bool enabled}) async {
    if (enabled && (await ref.read(wakeSpeakersProvider.future)).isEmpty) {
      return false;
    }
    final next = WakeServiceSettings(
      enabled: enabled,
      condition: (await future).condition,
    );
    state = AsyncData(next);
    await ref.read(storageProvider).settings.set(wakeEnabledKey, enabled);
    await push();
    return true;
  }

  /// Chooses when it listens.
  Future<void> setCondition(WakeCondition condition) async {
    state = AsyncData(
      WakeServiceSettings(
        enabled: (await future).enabled,
        condition: condition,
      ),
    );
    await ref
        .read(storageProvider)
        .settings
        .set(wakeConditionKey, condition.name);
    await push();
  }
}
