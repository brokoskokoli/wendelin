import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../voice/wake/utterance_capture.dart';
import '../../../voice/wake/wake_enroller.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../settings_page.dart';
import 'wake_lifecycle.dart';

/// Hint for recording [index] (0-based): near, far, quiet, normal.
String enrollHint(int index) => switch (index ~/ 4) {
  0 => 'Sprich normal, das Handy nah vor dir.',
  1 => 'Jetzt aus ein bis zwei Metern Abstand.',
  2 => 'Jetzt leise, wie abends im Zimmer.',
  _ => 'Wie du es im Alltag sagst, gern aus einer anderen Ecke.',
};

/// Text for the verdict on the latest recording.
String verdictText(UtteranceVerdict v) => switch (v) {
  UtteranceVerdict.accepted => 'Gehört.',
  UtteranceVerdict.noSpeech => 'Nichts gehört. Noch einmal bitte.',
  UtteranceVerdict.tooQuiet => 'Zu leise. Bitte etwas lauter.',
  UtteranceVerdict.cutOff => 'Zu früh angefangen. Warte kurz und sprich dann.',
  UtteranceVerdict.tooLong => 'Zu lang. Nur „Wendelin“, bitte.',
};

/// Einstellungen → Sprache → Aktivierungswort → „Stimme einlernen“:
/// Wendelin bittet etwa 15 Mal um „Wendelin“ (WP60). Aus jeder Aufnahme
/// wird sofort das Embedding berechnet, das Audio wird verworfen.
class WakeEnrollScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [speakerId] is replaced if it exists.
  const WakeEnrollScreen({
    super.key,
    required this.speakerId,
    required this.name,
  });

  /// Speaker to learn (existing ones are re-learned).
  final String speakerId;

  /// Display name (may be empty).
  final String name;

  @override
  ConsumerState<WakeEnrollScreen> createState() => _WakeEnrollScreenState();
}

class _WakeEnrollScreenState extends ConsumerState<WakeEnrollScreen>
    with WidgetsBindingObserver, WakeBackgroundAbort {
  WakeEnroller? _enroller;
  var _denied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final mic = ref.read(microphoneProvider);
    if (!await ensureMicrophoneAccess(context, mic)) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    if (!mounted) return;
    final e = WakeEnroller(
      audio: ref.read(wakeAudioProvider),
      features: ref.read(wakeFeaturesFactoryProvider)(),
      store: ref.read(wakeStoreProvider),
      speakerId: widget.speakerId,
      pause: ref.read(wakeEnrollPauseProvider),
    );
    setState(() => _enroller = e);
    await e.run();
  }

  @override
  Future<void> abortForBackground() async => _enroller?.cancel();

  @override
  void dispose() {
    final e = _enroller;
    if (e != null) {
      unawaited(e.cancel());
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _finish(WakeEnroller e) async {
    await e.finish();
    await ref
        .read(wakeSpeakersProvider.notifier)
        .upsert(widget.speakerId, widget.name);
    ref.invalidate(wakeTemplatesProvider(widget.speakerId));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final e = _enroller;
    if (_denied || e == null) {
      return SettingsPage(
        title: 'Stimme einlernen',
        children: [
          Text(
            _denied
                ? 'Ohne Mikrofon kann Wendelin deine Stimme nicht lernen.'
                : 'Mikrofon wird vorbereitet …',
            style: WText.intro,
          ),
        ],
      );
    }
    return ListenableBuilder(listenable: e, builder: (context, _) => _body(e));
  }

  Widget _body(WakeEnroller e) {
    final done = e.phase == EnrollPhase.complete;
    final failed = e.error != null;
    return SettingsPage(
      title: 'Stimme einlernen',
      intro:
          'Sag „Wendelin“, wenn du dran bist. Aus jeder Aufnahme behält '
          'Wendelin nur Zahlenwerte; das Audio wird sofort verworfen.',
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(WSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.m,
                children: [
                  Text(
                    '${e.accepted} von ${e.target}',
                    style: WText.screenTitle,
                  ),
                  LinearProgressIndicator(
                    value: e.accepted / e.target,
                    semanticsLabel: 'Fortschritt Einlernen',
                  ),
                  if (!done && !failed) ...[
                    Text(
                      e.phase == EnrollPhase.processing
                          ? 'Wird verarbeitet …'
                          : 'Sag jetzt: „Wendelin“',
                      style: WText.label,
                    ),
                    Text(enrollHint(e.accepted), style: WText.detail),
                    Waveform(
                      amplitudes: [for (var i = 0; i < 24; i++) _bar(e, i)],
                    ),
                  ],
                  if (e.lastVerdict != null && !done)
                    Text(verdictText(e.lastVerdict!), style: WText.caption),
                  if (done) Text('Alle Aufnahmen sind da.', style: WText.label),
                  if (failed)
                    Text(
                      'Das Einlernen ist gescheitert: ${e.error}',
                      style: WText.caption,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (done || e.canFinish)
          PrimaryButton(
            done ? 'Speichern' : 'Mit ${e.accepted} Aufnahmen speichern',
            onPressed: () => unawaited(_finish(e)),
          ),
        WideButton(
          'Abbrechen',
          onPressed: () async {
            await e.cancel();
            if (mounted) Navigator.of(context).pop(false);
          },
        ),
      ],
    );
  }

  double _bar(WakeEnroller e, int i) {
    final level = (e.level * 8).clamp(0.0, 1.0);
    return level * (0.4 + 0.6 * ((i * 7) % 10) / 10);
  }
}
