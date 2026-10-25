import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../voice/wake/wake_tester.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../settings_page.dart';
import 'wake_lifecycle.dart';

/// Text for the second stage of a test hit.
String confirmationText(AppLocalizations l, WakeConfirmation c) => switch (c) {
  WakeConfirmation.pending => l.wakeTestVerifying,
  WakeConfirmation.confirmed => l.wakeTestConfirmed,
  WakeConfirmation.rejected => l.wakeTestRejected,
  WakeConfirmation.unavailable => l.wakeTestUnavailable,
};

/// Name of the stage 2 recognizer [kind] (`WakeVerifier.kind`), `null` for
/// an unknown one.
String? verifierName(AppLocalizations l, String? kind) => switch (kind) {
  'b' => l.wakeTestVerifierB,
  'parakeet' => l.wakeTestVerifierParakeet,
  'whisper' => l.wakeTestVerifierWhisper,
  _ => null,
};

/// The confirmation of [e] with the recognizer that decided.
String confirmationDetail(AppLocalizations l, WakeTestEvent e) {
  final text = confirmationText(l, e.confirmation);
  final name = verifierName(l, e.decidedBy);
  return name == null ? text : l.wakeTestDecidedBy(text, name);
}

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
        title: context.l10n.wakeTestTitle,
        children: [
          Text(
            _denied
                ? context.l10n.wakeTestNoMic
                : context.l10n.wakeTestMicPreparing,
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
      intro: context.l10n.wakeTestIntro,
      children: [
        if (t.error != null)
          Text(context.l10n.wakeTestFailed(t.error!), style: WText.label)
        else
          Text(
            context.l10n.wakeTestBest(
              t.running
                  ? context.l10n.wakeTestListening
                  : context.l10n.wakeTestStopped,
              _fmt(t.maxSimilarity),
            ),
            style: WText.detail,
          ),
        if (events.isEmpty)
          Text(context.l10n.wakeTestNoHit, style: WText.caption)
        else
          SectionCard(
            children: [
              for (final e in events)
                SettingsRow(
                  title: context.l10n.wakeTestCandidate(_fmt(e.similarity)),
                  detail: context.l10n.wakeTestAgo(
                    confirmationDetail(context.l10n, e),
                    e.at.inSeconds,
                  ),
                ),
            ],
          ),
        WideButton(
          context.l10n.done,
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
