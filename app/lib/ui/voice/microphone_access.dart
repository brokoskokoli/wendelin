import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../platform/voice/record_audio_input.dart';
import '../../voice/voice_components.dart';
import '../design/design.dart';
import '../settings/settings_page.dart';

/// Explanation shown before Android asks for the microphone.
String microphoneExplanation(AppLocalizations l) => l.micExplanation;

/// Where the microphone permission is given once Android stops asking.
String microphoneSettingsHint(AppLocalizations l) => l.micSettingsHint;

/// Outcome of [requestMicrophoneAccess].
enum MicrophoneAccess {
  /// Granted (before or now).
  granted,

  /// „Nicht jetzt“ in Wendelin's explanation; Android was not asked.
  notNow,

  /// Android was asked and refused (maybe for good).
  denied,
}

/// Opens Android's app info of Wendelin, where the microphone can be
/// allowed (overridden in tests).
final appSettingsOpenerProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    try {
      await const AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:app.wendelin',
      ).launch();
    } on PlatformException {
      // No settings app: nothing to open.
    }
  },
);

/// Makes sure Wendelin may use the microphone: [MicrophoneAccess.granted]
/// right away if the permission is granted, otherwise explains why it is
/// needed and only then lets Android ask (concept: permissions on first
/// use). Call it when the user starts speaking or switches voice on.
Future<MicrophoneAccess> requestMicrophoneAccess(
  BuildContext context,
  PcmRecorder microphone,
) async {
  if (await microphone.hasPermission(request: false)) {
    return MicrophoneAccess.granted;
  }
  if (!context.mounted) return MicrophoneAccess.notNow;
  final ok = await confirm(
    context,
    title: context.l10n.micAllowTitle,
    message: microphoneExplanation(context.l10n),
    yes: context.l10n.allow,
    no: context.l10n.micNotNow,
  );
  if (!ok) return MicrophoneAccess.notNow;
  final granted = await microphone.hasPermission();
  if (!granted && context.mounted) {
    showHint(
      context,
      context.l10n.micOnlyText(microphoneSettingsHint(context.l10n)),
    );
  }
  return granted ? MicrophoneAccess.granted : MicrophoneAccess.denied;
}

/// [requestMicrophoneAccess] as yes/no.
Future<bool> ensureMicrophoneAccess(
  BuildContext context,
  PcmRecorder microphone,
) async =>
    await requestMicrophoneAccess(context, microphone) ==
    MicrophoneAccess.granted;

/// Card above the input row while the microphone is not allowed: „Ohne
/// Mikrofon-Zugriff geht nur Text.“ with „Erlauben“ (Android asks) or,
/// once Android refused, „Android-Einstellungen“.
class MicrophoneNotice extends StatelessWidget {
  /// Creates the notice.
  const MicrophoneNotice({
    super.key,
    required this.deniedByAndroid,
    required this.onAllow,
    required this.onOpenSettings,
  });

  /// Whether Android already refused (then only its settings help).
  final bool deniedByAndroid;

  /// „Erlauben“: lets Android ask.
  final VoidCallback onAllow;

  /// „Android-Einstellungen“: opens Wendelin's app info.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => StatusCard(
    status: CheckStatus.pending,
    title: microphoneDeniedHint,
    detail: deniedByAndroid ? microphoneSettingsHint(context.l10n) : null,
    actionBelow: deniedByAndroid,
    action: OutlinedButton(
      onPressed: deniedByAndroid ? onOpenSettings : onAllow,
      style: OutlinedButton.styleFrom(
        foregroundColor: WColors.text,
        side: const BorderSide(color: WColors.line, width: WSize.border),
        textStyle: WText.buttonSmall,
        minimumSize: const Size(WSize.touchMin, WSize.touchMin),
        padding: const EdgeInsets.symmetric(horizontal: WSpace.m14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WRadius.tile),
        ),
      ),
      child: Text(
        deniedByAndroid ? context.l10n.micAndroidSettings : context.l10n.allow,
      ),
    ),
  );
}
