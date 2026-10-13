import 'package:flutter/material.dart';

import '../../platform/voice/record_audio_input.dart';
import '../settings/settings_page.dart';

/// Explanation shown before Android asks for the microphone.
const microphoneExplanation =
    'Wendelin hört nur zu, nachdem du ihn ausgelöst hast (Mikrofontaste '
    'oder Assistent). Die Aufnahme wird auf dem Gerät in Text umgewandelt '
    'und verlässt es nicht; nur der erkannte Text geht an deinen Provider.';

/// Makes sure Wendelin may use the microphone: returns `true` right away if
/// the permission is granted, otherwise explains why it is needed and only
/// then lets Android ask (concept: permissions on first use). Call it when
/// the user starts speaking or switches voice on.
Future<bool> ensureMicrophoneAccess(
  BuildContext context,
  PcmRecorder microphone,
) async {
  if (await microphone.hasPermission(request: false)) return true;
  if (!context.mounted) return false;
  final ok = await confirm(
    context,
    title: 'Mikrofon erlauben?',
    message: microphoneExplanation,
    yes: 'Erlauben',
    no: 'Nicht jetzt',
  );
  if (!ok) return false;
  final granted = await microphone.hasPermission();
  if (!granted && context.mounted) {
    showHint(
      context,
      'Ohne Mikrofon geht nur Text. Du kannst es in den '
      'Android-Einstellungen unter Apps → Wendelin erlauben.',
    );
  }
  return granted;
}
