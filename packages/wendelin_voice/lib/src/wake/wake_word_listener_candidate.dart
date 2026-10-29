part of 'wake_word_listener.dart';

/// Candidate verification, dev clips, and detection emission for [WakeWordListener].
extension WakeWordListenerCandidate on WakeWordListener {
  // WP155/WP171: a window; a case is archived once its run is over.
  void _onWindow(WakeWindowScores w) {
    try {
      if (!_dev.on) {
        _shadow.reset();
        return;
      }
      final miss = _shadow.onWindow(w);
      if (miss == null) return;
      final c = noteShadowCase(devClips, miss, _above);
      if (c == null) return;
      _dev.startCase(
        () => _candidateClip(miss.clipEnd, 'near-miss', c, only: true),
        c,
      );
    } on Object {
      // Never into the voice path.
    }
  }

  void _startCandidateClip(int end, DevArchiveCase? arch) {
    if (arch != null) {
      _dev.startCase(() => _candidateClip(end, 'wake-cand', arch), arch);
    } else {
      _dev.start(() => _candidateClip(end, 'wake-cand', null));
    }
  }

  Future<bool> _waitForTail(
    int end,
    int tail,
    int gen,
    DevArchiveCase? arch,
  ) async {
    if (tail > 0 && _position < end + tail) {
      _tailTarget = end + tail;
      final wait = _tailWait = Completer<void>();
      await wait.future.timeout(verifyTimeout, onTimeout: () {});
      _tailWait = null;
      if (gen != _generation) {
        _ring.release(discard: true);
        arch?.finish('dropped', {'reason': 'stopped'});
        return false;
      }
    }
    return true;
  }

  Future<({bool ok, String verdict})> _verifyCandidate(
    WakeWordHit hit,
    int end,
    int tail,
    DevArchiveCase? arch,
    int gen,
  ) async {
    final v = verifier;
    final snap = _ring.snapshot();
    final snapStart = _position - snap.length;
    int rel(int abs) => (abs - snapStart).clamp(0, snap.length);
    final lead = Int16List.sublistView(
      snap,
      rel(end - durationToSamples(verifyWindow)),
      rel(end + tail),
    );
    var ok = true;
    var verdict = hit.direct ? 'direct' : (v == null ? 'unchecked' : 'ok');
    if (v != null && !hit.direct) {
      try {
        final at = rel(end) - rel(end - durationToSamples(verifyWindow));
        devClips?.emitMarked('wake-verify', lead, 'wakeEnd', at);
        noteVerifyClip(devClips, arch, 'wake-verify', lead, 'wakeEnd', at);
        ok =
            await (v is WakeEndAwareVerifier
                    ? v.confirmAt(lead, at)
                    : v.confirm(lead))
                .timeout(verifyTimeout);
        verdict = ok ? 'ok' : 'no';
      } on Object {
        ok = false; // a failing or slow verifier must not trigger
        verdict = 'error';
      }
      noteWakeVerdict(devClips, arch, v, verdict);
    }
    return (ok: ok, verdict: verdict);
  }

  void _emitDetection(WakeWordHit hit, int end) {
    final fullSnap = _ring.snapshot();
    final fullStart = _position - fullSnap.length;
    int fullRel(int abs) => (abs - fullStart).clamp(0, fullSnap.length);
    final preStart = fullRel(end - durationToSamples(preRoll));
    final out = Int16List.sublistView(fullSnap, preStart, fullSnap.length);
    final wakeEnd = fullRel(end) - preStart;
    _detections.add(
      WakeWordDetection(
        hit: hit,
        preRoll: out,
        latency: samplesToDuration(_position - end),
        wakeEnd: wakeEnd.clamp(0, out.length),
        position: _position,
      ),
    );
  }

  // The candidate at stream position [end] with what lies around it (WP148).
  DevAround _candidateClip(
    int end,
    String event,
    DevArchiveCase? archiveCase, {
    bool only = false,
  }) {
    final snap = _ring.snapshot();
    final start = _position - snap.length;
    int rel(int abs) => (abs - start).clamp(0, snap.length);
    final span = durationToSamples(devClipSpan);
    return DevAround(
      event: event,
      before: Int16List.sublistView(snap, rel(end - span), rel(end)),
      already: Int16List.sublistView(snap, rel(end)),
      afterWanted: span,
      archiveCase: archiveCase,
      archiveOnly: only,
    );
  }
}
