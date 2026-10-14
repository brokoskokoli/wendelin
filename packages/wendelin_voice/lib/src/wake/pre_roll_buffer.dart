import 'dart:typed_data';

import '../io/audio_input.dart';

/// Ring buffer of the most recent PCM samples (default 300 ms, concept).
///
/// The capacity is a hard upper bound: older samples are dropped, so no
/// audio is ever buffered without limit.
final class PreRollBuffer {
  /// Creates a buffer holding the last [capacity] (at most [maxCapacity]).
  PreRollBuffer({this.capacity = defaultCapacity}) {
    if (capacity <= Duration.zero || capacity > maxCapacity) {
      throw ArgumentError.value(
        capacity,
        'capacity',
        'must be in (0, $maxCapacity]',
      );
    }
    _ring = Int16List(durationToSamples(capacity));
  }

  /// Default pre-roll length.
  static const defaultCapacity = Duration(milliseconds: 300);

  /// Largest allowed capacity.
  static const maxCapacity = Duration(seconds: 5);

  /// Time span kept.
  final Duration capacity;

  late final Int16List _ring;
  int _head = 0; // next write position
  int _filled = 0;

  /// Number of samples currently held.
  int get length => _filled;

  /// Appends [frame]; samples beyond the capacity push out the oldest.
  void add(Int16List frame) {
    var src = frame;
    if (src.length >= _ring.length) {
      src = Int16List.sublistView(src, src.length - _ring.length);
      _ring.setAll(0, src);
      _head = 0;
      _filled = _ring.length;
      return;
    }
    final first = _ring.length - _head;
    if (src.length <= first) {
      _ring.setRange(_head, _head + src.length, src);
    } else {
      _ring.setRange(_head, _ring.length, src);
      _ring.setRange(0, src.length - first, src, first);
    }
    _head = (_head + src.length) % _ring.length;
    _filled = _filled + src.length > _ring.length
        ? _ring.length
        : _filled + src.length;
  }

  /// The held samples, oldest first. With [last] only that many samples.
  Int16List snapshot({Duration? last}) {
    var n = _filled;
    if (last != null) {
      final want = durationToSamples(last);
      if (want < n) n = want;
    }
    final out = Int16List(n);
    final start = (_head - n) % _ring.length;
    final first = _ring.length - start;
    if (n <= first) {
      out.setRange(0, n, _ring, start);
    } else {
      out.setRange(0, first, _ring, start);
      out.setRange(first, n, _ring);
    }
    return out;
  }

  /// Forgets everything.
  void clear() {
    _head = 0;
    _filled = 0;
  }
}
