import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/preferences.dart';
import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../voice/wake/wake_calibrator.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../settings_page.dart';
import 'wake_lifecycle.dart';

/// „Kalibrieren“ (WP60): the phone lies around for about 30 minutes, the
/// screen stays on (only here), the microphone indicator is visible. Only
/// similarity numbers are collected; now and then a tone asks for
/// „Wendelin“. Ends with the threshold and the expected false alarms.
class WakeCalibrateScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [templates].
  const WakeCalibrateScreen({
    super.key,
    required this.templates,
    this.duration = const Duration(minutes: 30),
  });

  /// Templates to calibrate.
  final WakeTemplates templates;

  /// Listening time.
  final Duration duration;

  @override
  ConsumerState<WakeCalibrateScreen> createState() => _State();
}

class _State extends ConsumerState<WakeCalibrateScreen>
    with WidgetsBindingObserver, WakeBackgroundAbort {
  WakeCalibrator? _cal;
  var _denied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!await ensureMicrophoneAccess(context, ref.read(microphoneProvider))) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    if (!mounted) return;
    final protection = ref.read(screenProtectionProvider);
    final cal = WakeCalibrator(
      audio: ref.read(wakeAudioProvider),
      features: ref.read(wakeFeaturesFactoryProvider)(),
      templates: widget.templates,
      store: ref.read(wakeStoreProvider),
      onPrompt: ref.read(wakePromptToneProvider),
      duration: widget.duration,
    );
    setState(() => _cal = cal);
    await protection.keepScreenOn(on: true);
    try {
      // Left (or sent to the background) while the screen lock was being
      // set: never start the microphone.
      if (mounted && cal.phase == CalibrationPhase.idle) await cal.run();
    } finally {
      await protection.keepScreenOn(on: false);
    }
    if (cal.stored) {
      ref.invalidate(wakeTemplatesProvider(widget.templates.speakerId));
    }
  }

  @override
  Future<void> abortForBackground() async {
    final c = _cal;
    if (c != null &&
        (c.phase == CalibrationPhase.listening ||
            c.phase == CalibrationPhase.idle)) {
      await c.cancel();
    }
  }

  @override
  void dispose() {
    unawaited(abortForBackground());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _cal;
    if (_denied || c == null) {
      return SettingsPage(
        title: 'Kalibrieren',
        children: [
          Text(
            _denied
                ? 'Ohne Mikrofon kann Wendelin nicht kalibrieren.'
                : 'Mikrofon wird vorbereitet …',
            style: WText.intro,
          ),
        ],
      );
    }
    return ListenableBuilder(listenable: c, builder: (_, _) => _body(c));
  }

  Widget _body(WakeCalibrator c) {
    final r = c.result;
    final total = widget.duration;
    final left = total - c.elapsed;
    return SettingsPage(
      title: 'Kalibrieren',
      intro:
          'Leg das Handy hin und red normal weiter. Wendelin hört mit '
          '(Mikrofonanzeige an), merkt sich aber nur Zahlenwerte, kein Audio '
          'und keinen Text. Ab und zu piept es: Sag dann „Wendelin“.',
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(WSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.m,
                children: [
                  if (c.phase == CalibrationPhase.listening) ...[
                    Text(
                      'Noch ${left.inMinutes + (left.inSeconds % 60 > 0 ? 1 : 0)} min',
                      style: WText.screenTitle,
                    ),
                    LinearProgressIndicator(
                      value: (c.elapsed.inSeconds / total.inSeconds).clamp(
                        0.0,
                        1.0,
                      ),
                      semanticsLabel: 'Fortschritt Kalibrieren',
                    ),
                    Text(
                      'Aufforderungen: ${c.answered} von ${c.prompts} '
                      'beantwortet',
                      style: WText.detail,
                    ),
                  ],
                  if (r != null) ..._result(c, r),
                  if (c.phase == CalibrationPhase.cancelled)
                    Text(
                      c.error != null
                          ? 'Gescheitert: ${c.error}'
                          : 'Abgebrochen. Es wurde nichts geändert.',
                      style: WText.label,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (c.canFinishEarly) WideButton('Jetzt beenden', onPressed: c.finish),
        if (c.phase == CalibrationPhase.listening)
          WideButton(
            'Abbrechen',
            onPressed: () async {
              await c.cancel();
              if (mounted) Navigator.of(context).pop();
            },
          )
        else
          PrimaryButton('Fertig', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  List<Widget> _result(WakeCalibrator c, WakeCalibration r) => [
    Text(
      r.meetsTarget ? 'Kalibriert.' : 'Nicht verwertbar.',
      style: WText.screenTitle,
    ),
    Text(
      r.meetsTarget
          ? 'Schwelle ${r.threshold.toStringAsFixed(2)} · geschätzt '
                '${r.falseAlarmsPerHour.toStringAsFixed(1)} Fehlalarme pro '
                'Stunde (vor der Nachprüfung) · ${(r.recall * 100).round()} % '
                'deiner Aufnahmen erkannt.'
          : 'Deine Aufnahmen heben sich nicht vom Hintergrund ab. Lerne '
                'deine Stimme bitte noch einmal ein. Die alte Schwelle bleibt.',
      style: WText.detail,
    ),
  ];
}
