import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../voice/wake/wake_tester.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../settings_page.dart';
import 'wake_lifecycle.dart';

/// Text for the second stage of a test hit.
String confirmationText(WakeConfirmation c) => switch (c) {
  WakeConfirmation.pending => 'Nachprüfung läuft …',
  WakeConfirmation.confirmed => 'Nachprüfung: bestätigt',
  WakeConfirmation.rejected => 'Nachprüfung: nicht bestätigt',
  WakeConfirmation.unavailable => 'Nachprüfung: nicht möglich (kein Whisper)',
};

/// „Jetzt ausprobieren“ (WP60): shows every candidate and, apart from it,
/// whether Whisper confirmed it. The overlay does not open. The test always
/// runs stage 2, whatever the setting for everyday use says.
class WakeTestScreen extends ConsumerStatefulWidget {
  /// Creates the screen for the learned [speakers].
  const WakeTestScreen({super.key, required this.speakers});

  /// Templates of all speakers.
  final List<WakeTemplates> speakers;

  @override
  ConsumerState<WakeTestScreen> createState() => _WakeTestScreenState();
}

class _WakeTestScreenState extends ConsumerState<WakeTestScreen>
    with WidgetsBindingObserver, WakeBackgroundAbort {
  WakeTester? _tester;
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
    final verifier = await ref.read(wakeVerifierProvider.future);
    if (!mounted) return;
    final t = WakeTester(
      audio: ref.read(wakeAudioProvider),
      features: ref.read(wakeFeaturesFactoryProvider)(),
      speakers: widget.speakers,
      verifier: verifier,
    );
    setState(() => _tester = t);
    await t.run();
  }

  @override
  Future<void> abortForBackground() async => _tester?.stop();

  @override
  void dispose() {
    unawaited(_tester?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _tester;
    if (_denied || t == null) {
      return SettingsPage(
        title: 'Ausprobieren',
        children: [
          Text(
            _denied
                ? 'Ohne Mikrofon geht der Test nicht.'
                : 'Mikrofon wird vorbereitet …',
            style: WText.intro,
          ),
        ],
      );
    }
    return ListenableBuilder(listenable: t, builder: (_, _) => _body(t));
  }

  Widget _body(WakeTester t) {
    final events = t.events.reversed.toList();
    return SettingsPage(
      title: 'Ausprobieren',
      intro:
          'Sag „Wendelin“. Hier erscheinen Treffer, ohne dass das Overlay '
          'aufgeht. „Kandidat“ ist die Stimme, „bestätigt“ die Nachprüfung '
          'mit Whisper.',
      children: [
        if (t.error != null)
          Text('Gescheitert: ${t.error}', style: WText.label)
        else
          Text(
            '${t.running ? 'Hört zu' : 'Angehalten'} · höchste Ähnlichkeit '
            '${_fmt(t.maxSimilarity)}',
            style: WText.detail,
          ),
        if (events.isEmpty)
          Text('Noch kein Treffer.', style: WText.caption)
        else
          SectionCard(
            children: [
              for (final e in events)
                SettingsRow(
                  title: 'Kandidat · Ähnlichkeit ${_fmt(e.similarity)}',
                  detail:
                      '${confirmationText(e.confirmation)} · '
                      '${e.at.inSeconds} s',
                ),
            ],
          ),
        WideButton(
          'Fertig',
          onPressed: () async {
            await t.stop();
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  String _fmt(double v) => v < 0 ? '–' : v.toStringAsFixed(2);
}
