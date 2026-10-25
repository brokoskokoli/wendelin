import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Collects the asynchronous frees that providers start when they are
/// disposed (WP145), so the overlay can wait for them (bounded) before its
/// engine ends: native objects (ORT/sherpa sessions, sqlite) that are still
/// open then are not freed by the Dart VM.
final class DisposeTracker {
  final _pending = <Future<void>>{};

  /// Number of frees that have not finished.
  int get pending => _pending.length;

  /// Number of frees tracked so far (finished or not).
  int get tracked => _tracked;
  int _tracked = 0;

  /// Remembers [free]; its failure is swallowed (nothing left to report to).
  void track(Future<void> free) {
    _tracked++;
    late final Future<void> guarded;
    guarded = free.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      _pending.remove(guarded);
    });
    _pending.add(guarded);
  }

  /// Whether the engine ends (the container is disposed for good, not a
  /// provider rebuilt): a model may then be freed even though another engine
  /// still uses it (its isolate goes with the engine, WP146).
  bool get ending => _ending;
  bool _ending = false;

  /// Marks the end of the engine; set before the container is disposed.
  void markEnding() => _ending = true;

  /// Completes when everything tracked so far (and what it starts) is done.
  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }
}

/// One tracker per container (engine).
final disposeTrackerProvider = Provider<DisposeTracker>(
  (ref) => DisposeTracker(),
);

/// `ref.onDispose` for a native free that is asynchronous: [free] runs when
/// the provider is disposed and the overlay can wait for it.
void onDisposeTracked(Ref ref, Future<void> Function() free) {
  final tracker = ref.read(disposeTrackerProvider);
  ref.onDispose(() => tracker.track(free()));
}
