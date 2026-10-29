import 'dart:math' as math;
import 'dart:typed_data';

import '../io/audio_input.dart';

/// Ring buffer of the most recent PCM samples (WP178).
///
/// Keeps rolling 5–6 seconds of audio history (default 5 s, minimum 5 s)
/// and supports candidate hold (buffer grows and retains all audio while held),
/// slices, ranges, and snapshots.
final class AudioRingBuffer {
  /// Creates a buffer holding at least [capacity] (default 5 s, at most [maxCapacity]).
  AudioRingBuffer({
    this.capacity = defaultCapacity,
    Duration maxCapacity = defaultMaxCapacity,
  }) : maxLimit = maxCapacity {
    if (capacity <= Duration.zero || capacity > maxLimit) {
      throw ArgumentError.value(
        capacity,
        'capacity',
        'must be in (0, $maxLimit]',
      );
    }
    _capacitySamples = durationToSamples(capacity);
    _ring = Int16List(_capacitySamples);
  }

  /// Default ring buffer capacity (5 seconds, adhering to WP178 5–6 s requirement).
  static const defaultCapacity = Duration(seconds: 5);

  /// Safety maximum capacity (60 seconds) to prevent unbounded memory growth.
  static const defaultMaxCapacity = Duration(seconds: 60);

  /// Alias for safety maximum capacity.
  static const maxCapacity = defaultMaxCapacity;

  /// Time span kept when rolling.
  final Duration capacity;

  /// Largest allowed capacity.
  final Duration maxLimit;

  late int _capacitySamples;

  /// Capacity in number of samples.
  int get capacityInSamples => _capacitySamples;

  late Int16List _ring;
  int _head = 0; // next write position
  int _filled = 0;
  bool _held = false;

  /// Whether the buffer is held (growing during candidate verification).
  bool get isHeld => _held;

  /// Number of samples currently held.
  int get length => _filled;

  /// Audio duration currently held.
  Duration get duration => samplesToDuration(_filled);

  /// Appends [frame]. When not held, samples beyond capacity push out the oldest.
  /// When held, older samples are preserved and the buffer grows.
  void add(Int16List frame) {
    if (frame.isEmpty) return;

    if (_held) {
      // While held, we append and grow without dropping anything.
      if (_filled + frame.length > _ring.length) {
        final newCap = math.max(
          _ring.length * 2,
          _filled + frame.length + _capacitySamples,
        );
        final newRing = Int16List(newCap);
        newRing.setRange(0, _filled, _ring);
        _ring = newRing;
      }
      _ring.setRange(_filled, _filled + frame.length, frame);
      _filled += frame.length;
      _head = _filled;
      return;
    }

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

  /// Puts the buffer into held mode. While held, incoming audio is appended
  /// without dropping any older samples so that verification can take as long
  /// as needed without losing the candidate or subsequent audio.
  void hold() {
    if (_held) return;
    // Unroll existing ring into a contiguous linear buffer starting at 0
    final snap = snapshot();
    if (_ring.length < snap.length) {
      _ring = Int16List(math.max(_capacitySamples, snap.length));
    }
    _ring.setRange(0, snap.length, snap);
    _head = snap.length;
    _filled = snap.length;
    _held = true;
  }

  /// Releases the hold. If [discard] is true (candidate rejected / false alarm),
  /// excess audio older than [capacity] is dropped and the buffer resumes rolling
  /// with the most recent [capacity] samples.
  /// If [discard] is false (candidate confirmed), all accumulated audio is kept.
  void release({bool discard = false}) {
    if (!_held) return;
    _held = false;
    if (discard) {
      if (_filled > _capacitySamples) {
        final kept = snapshot(last: capacity);
        _ring = Int16List(_capacitySamples);
        _ring.setRange(0, kept.length, kept);
        _head = kept.length % _capacitySamples;
        _filled = kept.length;
      } else {
        _head = _filled % _capacitySamples;
      }
    } else {
      // Confirmed: unroll contiguous
      final snap = snapshot();
      _ring = Int16List(math.max(_capacitySamples, snap.length));
      _ring.setRange(0, snap.length, snap);
      _head = snap.length;
      _filled = snap.length;
    }
  }

  /// The held samples, oldest first. With [last] only that many samples.
  Int16List snapshot({Duration? last}) {
    var n = _filled;
    if (last != null) {
      final want = durationToSamples(last);
      if (want < n) n = want;
    }
    final out = Int16List(n);
    if (n == 0) return out;

    if (_held || _head == _filled) {
      // Linear layout
      final start = _filled - n;
      out.setRange(0, n, _ring, start);
      return out;
    }

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

  /// Extracts a range of samples by index [start] to [end] (oldest held sample is index 0).
  Int16List range(int start, int end) {
    if (_filled == 0 || end <= start) return Int16List(0);
    final s = start.clamp(0, _filled);
    final e = end.clamp(0, _filled);
    final count = e - s;
    if (count <= 0) return Int16List(0);

    final snap = snapshot();
    return Int16List.sublistView(snap, s, e);
  }

  /// Extracts a time slice from the buffer.
  Int16List slice({
    Duration? from,
    Duration? duration,
    int? fromSample,
    int? sampleCount,
  }) {
    final start = fromSample ?? (from != null ? durationToSamples(from) : 0);
    final count =
        sampleCount ??
        (duration != null ? durationToSamples(duration) : _filled - start);
    return range(start, start + count);
  }

  /// Forgets everything and zeroes held memory.
  void clear() {
    _ring.fillRange(0, _ring.length, 0);
    _head = 0;
    _filled = 0;
    _held = false;
    if (_ring.length != _capacitySamples) {
      _ring = Int16List(_capacitySamples);
    }
  }
}
