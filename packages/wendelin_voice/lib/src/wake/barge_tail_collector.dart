import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../io/barge_in_detector.dart';

/// The audio a detached barge-in recording delivers after the answer (WP146):
/// frames since [begin], the arrival of the last one, and the guard that ends
/// the recording if nobody takes the tail.
final class BargeTailCollector {
  BargeTailCollector(this.clock, this.max);

  final Clock clock;

  /// Longest time the recording runs without being taken.
  final Duration max;

  final _frames = <Int16List>[];
  int _samples = 0;
  DateTime? _last;
  Timer? _guard;

  bool active = false;

  void begin(void Function() onTimeout) {
    active = true;
    _last = clock.now();
    _guard = Timer(max, onTimeout);
  }

  void add(Int16List frame) {
    _frames.add(frame);
    _samples += frame.length;
    _last = clock.now();
  }

  /// The collected audio with the time since its last frame; resets.
  BargeTail take() {
    final out = Int16List(_samples);
    var at = 0;
    for (final f in _frames) {
      out.setAll(at, f);
      at += f.length;
    }
    final idle = clock.now().difference(_last ?? clock.now());
    clear();
    return (pcm: out, idle: idle);
  }

  /// Forgets the audio and the guard (not the recording).
  void clear() {
    active = false;
    _guard?.cancel();
    _guard = null;
    _frames.clear();
    _samples = 0;
  }
}
