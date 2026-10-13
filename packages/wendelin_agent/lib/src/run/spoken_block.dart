/// Splits the `<spoken>…</spoken>` block (WP41, stage 2) from the streamed
/// text of one model call. Internal to `wendelin_agent`, not exported.
library;

/// Output of [SpokenBlockSplitter]: `spoken` once the block is complete,
/// `text` is the written answer (what is shown, recorded and passed on).
typedef SplitText = ({String text, String? spoken});

/// Cuts a leading `<spoken>…</spoken>` block from a text stream.
///
/// - The block counts only at the very start (after whitespace). Any other
///   start means plain text: everything is passed through unchanged.
/// - The block is reported once, when it is complete, so the speech output
///   never gets a half sentence of a broken block.
/// - A block that never ends (stream ends, or longer than [maxBlock]) is
///   broken: its content is passed on as ordinary text and nothing is
///   reported as spoken – the caller falls back to speaking the text.
final class SpokenBlockSplitter {
  /// Creates a splitter.
  SpokenBlockSplitter({this.maxBlock = 1200});

  static const _open = '<spoken>';
  static const _close = '</spoken>';

  /// Longest accepted block (characters).
  final int maxBlock;

  _Phase _phase = _Phase.start;
  String _buffer = '';
  bool _trimNext = false;

  /// Adds [delta]; returns what can be passed on now.
  SplitText add(String delta) {
    switch (_phase) {
      case _Phase.text:
        if (!_trimNext) return (text: delta, spoken: null);
        final t = delta.trimLeft(); // blank lines after the block
        if (t.isNotEmpty) _trimNext = false;
        return (text: t, spoken: null);
      case _Phase.start:
        _buffer += delta;
        final t = _buffer.trimLeft();
        if (t.length < _open.length && _open.startsWith(t)) {
          return (text: '', spoken: null); // could still become the tag
        }
        if (!t.startsWith(_open)) return _release();
        _phase = _Phase.block;
        _buffer = t.substring(_open.length);
        return _inBlock();
      case _Phase.block:
        _buffer += delta;
        return _inBlock();
    }
  }

  /// Ends the stream: returns held-back text (a broken block becomes text).
  SplitText finish() {
    switch (_phase) {
      case _Phase.text:
        return (text: '', spoken: null);
      case _Phase.start:
        return _release();
      case _Phase.block:
        return _release(text: _buffer);
    }
  }

  SplitText _inBlock() {
    final end = _buffer.indexOf(_close);
    if (end < 0) {
      if (_buffer.length > maxBlock) return _release(text: _buffer);
      return (text: '', spoken: null);
    }
    final spoken = _buffer.substring(0, end).trim();
    final rest = _buffer.substring(end + _close.length).trimLeft();
    _phase = _Phase.text;
    _trimNext = rest.isEmpty;
    _buffer = '';
    return (text: rest, spoken: spoken.isEmpty ? null : spoken);
  }

  SplitText _release({String? text}) {
    final out = text ?? _buffer;
    _phase = _Phase.text;
    _buffer = '';
    return (text: out.trimLeft(), spoken: null);
  }
}

enum _Phase { start, block, text }
