import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../voice/wake/utterance_capture.dart';
import '../../../voice/wake/wake_enroller.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../settings_page.dart';
import 'wake_lifecycle.dart';

/// Hint for recording [index] (0-based): near, far, quiet, normal.
String enrollHint(AppLocalizations l, int index, {int perStep = 4}) =>
    switch (index ~/ perStep) {
      0 => l.wakeEnrollPrompt0,
      1 => l.wakeEnrollPrompt1,
      2 => l.wakeEnrollPrompt2,
      _ => l.wakeEnrollPrompt3,
    };

/// Text for the verdict on the latest recording.
String verdictText(AppLocalizations l, UtteranceVerdict v, {String? word}) =>
    switch (v) {
      UtteranceVerdict.accepted => l.wakeEnrollHeard,
      UtteranceVerdict.noSpeech => l.wakeEnrollNoSpeech,
      UtteranceVerdict.tooQuiet => l.wakeEnrollTooQuiet,
      UtteranceVerdict.cutOff => l.wakeEnrollTooEarly,
      UtteranceVerdict.tooLong => l.wakeEnrollTooLong(
        word ?? l.wakeEnrollSpokenWord(l.appName),
      ),
      UtteranceVerdict.notWord => l.wakeEnrollNotWord(
        word ?? l.wakeEnrollSpokenWord(l.appName),
      ),
      UtteranceVerdict.missingHey => l.wakeEnrollMissingHey(
        word ?? l.wakeEnrollSpokenWord(l.appName),
      ),
      UtteranceVerdict.inconsistent => l.wakeEnrollInconsistent,
      UtteranceVerdict.unchecked => l.wakeEnrollUnchecked,
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
    final makeFeatures = await ref.read(
      wakeEnrollFeaturesFactoryProvider.future,
    );
    final verifier = await _verifier();
    if (!mounted) return;
    final e = WakeEnroller(
      audio: ref.read(wakeAudioProvider),
      features: makeFeatures(),
      store: ref.read(wakeStoreProvider),
      speakerId: widget.speakerId,
      target: 15,
      minimum: 8,
      threshold: wakeProvisionalThreshold,
      pause: ref.read(wakeEnrollPauseProvider),
      verifier: verifier,
    );
    setState(() => _enroller = e);
    await e.run();
  }

  /// The configured recognizer for the content check (`null`: not available,
  /// the enroller then rejects what the classifier does not vouch for).
  Future<WakeEnrollVerifier?> _verifier() async {
    try {
      // Wait for the recognizer while it loads, but not for ever.
      return await ref
          .read(wakeEnrollVerifierProvider.future)
          .timeout(ref.read(wakeEnrollVerifierWaitProvider));
    } on Object {
      return null;
    }
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
        title: context.l10n.wakeEnrollTitle,
        children: [
          Text(
            _denied
                ? context.l10n.wakeEnrollNoMic
                : context.l10n.wakeEnrollMicPreparing,
            style: WText.intro,
          ),
        ],
      );
    }
    return ListenableBuilder(listenable: e, builder: (context, _) => _body(e));
  }

  /// Setup hint before the first recording, tip after repeated quiet ones,
  /// verdict on the latest recording and the count of rejected ones.
  List<Widget> _hints(
    WakeEnroller e, {
    required bool done,
    required bool failed,
  }) {
    final l = context.l10n;
    final word = l.wakeEnrollSpokenWord(l.appName);
    return [
      if (!done && !failed && e.accepted == 0 && e.rejected == 0)
        Text(l.wakeEnrollSetupHint, style: WText.caption),
      if (!done && !failed && e.showQuietTip)
        Text(l.wakeEnrollQuietTip, style: WText.caption),
      if (e.lastVerdict != null && !done)
        Text(verdictText(l, e.lastVerdict!, word: word), style: WText.caption),
      if (e.rejected > 0)
        Text(l.wakeEnrollRejected(e.rejected), style: WText.caption),
    ];
  }

  Widget _body(WakeEnroller e) {
    final done = e.phase == EnrollPhase.complete;
    final failed = e.error != null;
    final word = context.l10n.wakeEnrollSpokenWord(context.l10n.appName);
    return SettingsPage(
      title: context.l10n.wakeWordEnroll,
      intro: context.l10n.wakeEnrollIntro(word),
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
                    context.l10n.wakeEnrollProgress(e.accepted, e.target),
                    style: WText.screenTitle,
                  ),
                  LinearProgressIndicator(
                    value: e.accepted / e.target,
                    semanticsLabel: context.l10n.wakeEnrollProgressLabel,
                  ),
                  if (!done && !failed) ...[
                    Text(
                      e.phase == EnrollPhase.processing
                          ? context.l10n.wakeEnrollProcessing
                          : context.l10n.wakeEnrollSayNow(word),
                      style: WText.label,
                    ),
                    Text(
                      enrollHint(context.l10n, e.accepted),
                      style: WText.detail,
                    ),
                    Waveform(
                      amplitudes: [for (var i = 0; i < 24; i++) _bar(e, i)],
                    ),
                  ],
                  ..._hints(e, done: done, failed: failed),
                  if (done)
                    Text(context.l10n.wakeEnrollAllThere, style: WText.label),
                  if (failed)
                    Text(
                      e.error is EnrollCheckUnavailable
                          ? context.l10n.wakeEnrollNoRecognizer
                          : context.l10n.wakeEnrollFailed(e.error!),
                      style: WText.caption,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (done || e.canFinish)
          PrimaryButton(
            done
                ? context.l10n.save
                : context.l10n.wakeEnrollSaveWith(e.accepted),
            onPressed: () => unawaited(_finish(e)),
          ),
        WideButton(
          context.l10n.cancel,
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
