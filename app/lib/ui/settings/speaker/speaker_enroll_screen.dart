import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/speaker_providers.dart';
import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../voice/speaker/speaker_recording.dart';
import '../../../voice/wake/utterance_capture.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../settings_page.dart';

/// Number of enrollment sentences.
const speakerSentenceCount = 5;

/// Sentence [index] (0-based) in the app language.
String speakerSentence(AppLocalizations l, int index) => switch (index) {
  0 => l.speakerSentence1,
  1 => l.speakerSentence2,
  2 => l.speakerSentence3,
  3 => l.speakerSentence4,
  _ => l.speakerSentence5,
};

/// Einstellungen → Sprache → Sprechererkennung → „Person einlernen“
/// (WP92a): [speakerSentenceCount] sentences are read aloud; each recording
/// becomes an embedding in the identifier, the audio is dropped. Shows the
/// calibration result at the end.
class SpeakerEnrollScreen extends ConsumerStatefulWidget {
  /// Creates the screen for the person [name].
  const SpeakerEnrollScreen({super.key, required this.name});

  /// Name of the person.
  final String name;

  @override
  ConsumerState<SpeakerEnrollScreen> createState() => _EnrollState();
}

class _EnrollState extends ConsumerState<SpeakerEnrollScreen> {
  final _samples = <Int16List>[];
  var _denied = false;
  var _processing = false;
  var _disposed = false;
  UtteranceVerdict? _verdict;
  SpeakerEnrollResult? _result;
  SpeakerEnrollProblem? _problem;
  late final AudioInput _audio = ref.read(wakeAudioProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_audio.stop());
    super.dispose();
  }

  Future<void> _run() async {
    if (!await ensureMicrophoneAccess(context, ref.read(microphoneProvider))) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    while (!_disposed && _samples.length < speakerSentenceCount) {
      final Utterance? u;
      try {
        u = await recordSentence(_audio);
      } on Object {
        if (mounted) setState(() => _problem = SpeakerEnrollProblem.failed);
        return;
      }
      if (_disposed || u == null) return;
      if (u.verdict == UtteranceVerdict.accepted) {
        _samples.add(u.pcm!);
        _verdict = null;
      } else {
        _verdict = u.verdict;
      }
      setState(() {});
    }
    if (_disposed) return;
    setState(() => _processing = true);
    try {
      final result = await ref
          .read(speakerProfilesProvider.notifier)
          .enroll(name: widget.name, samples: List.of(_samples));
      if (mounted) setState(() => _result = result);
    } on SpeakerEnrollException catch (e) {
      if (mounted) setState(() => _problem = e.problem);
    } on Object {
      if (mounted) setState(() => _problem = SpeakerEnrollProblem.failed);
    } finally {
      _samples.clear(); // never keep the audio longer than needed
      if (mounted) setState(() => _processing = false);
    }
  }

  void _again() {
    setState(() {
      _problem = null;
      _result = null;
      _verdict = null;
    });
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SettingsPage(
      title: l.speakerEnrollTitle,
      intro: l.speakerEnrollIntro,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(WSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.m,
                children: _content(l),
              ),
            ),
          ],
        ),
        if (_result != null)
          PrimaryButton(
            l.speakerDone,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        if (_problem != null) PrimaryButton(l.speakerRetry, onPressed: _again),
        if (_result == null)
          WideButton(
            l.cancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
      ],
    );
  }

  List<Widget> _content(AppLocalizations l) {
    if (_denied) return [Text(l.speakerNoMic, style: WText.label)];
    final result = _result;
    if (result != null) {
      String f(double v) => v.toStringAsFixed(2);
      return [
        Text(l.speakerResultTitle, style: WText.screenTitle),
        Text(
          l.speakerResultScores(
            f(result.meanScore),
            f(result.minScore),
            f(result.profile.threshold),
          ),
          style: WText.detail,
        ),
        if (result.thresholdClamped)
          Text(l.speakerResultClamped, style: WText.caption),
      ];
    }
    final problem = _problem;
    if (problem != null) {
      return [
        Text(switch (problem) {
          SpeakerEnrollProblem.tooFewSamples => l.speakerErrTooFew,
          SpeakerEnrollProblem.tooShort => l.speakerErrTooShort,
          SpeakerEnrollProblem.inconsistent => l.speakerErrInconsistent,
          SpeakerEnrollProblem.failed => l.speakerErrFailed,
        }, style: WText.label),
      ];
    }
    if (_processing) return [Text(l.speakerProcessing, style: WText.label)];
    final n = _samples.length;
    return [
      Text(
        l.speakerSentenceOf(n + 1, speakerSentenceCount),
        style: WText.screenTitle,
      ),
      LinearProgressIndicator(
        value: n / speakerSentenceCount,
        semanticsLabel: l.speakerSentenceOf(n + 1, speakerSentenceCount),
      ),
      Text(l.speakerSayNow, style: WText.caption),
      Text(speakerSentence(l, n), style: WText.label),
      if (_verdict != null)
        Text(switch (_verdict!) {
          UtteranceVerdict.accepted => '',
          UtteranceVerdict.noSpeech => l.speakerRecordNoSpeech,
          UtteranceVerdict.tooQuiet => l.speakerRecordTooQuiet,
          UtteranceVerdict.cutOff => l.speakerRecordCutOff,
          UtteranceVerdict.tooLong => l.speakerRecordTooLong,
        }, style: WText.caption),
    ];
  }
}
