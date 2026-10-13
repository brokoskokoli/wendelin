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
/// - Tags are recognised in any letter case.
/// - A block that never ends (stream ends) is broken: its content is passed
///   on as ordinary text and nothing is reported as spoken – the caller
///   falls back to speaking the text.
/// - A block longer than [maxBlock] is not spoken either; its content is
///   held back until the closing tag (which never becomes visible) and then
///   dropped. Without a closing tag it is passed on as text at the end.
final class SpokenBlockSplitter {
  /// Creates a splitter.
  SpokenBlockSplitter({this.maxBlock = 1200});

  static const _open = '<spoken>';
  static const _close = '</spoken>';
  static final _closeTag = RegExp(_close, caseSensitive: false);

  /// Longest accepted block (characters).
  final int maxBlock;

  _Phase _phase = _Phase.start;
  String _buffer = '';
  bool _trimNext = false;
  bool _tooLong = false;

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
        if (t.length < _open.length && _open.startsWith(t.toLowerCase())) {
          return (text: '', spoken: null); // could still become the tag
        }
        if (t.length < _open.length ||
            t.substring(0, _open.length).toLowerCase() != _open) {
          return _release();
        }
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
    final match = _closeTag.firstMatch(_buffer);
    if (match == null) {
      if (_buffer.length > maxBlock) _tooLong = true;
      return (text: '', spoken: null);
    }
    final spoken = _tooLong || match.start > maxBlock
        ? ''
        : _buffer.substring(0, match.start).trim();
    final rest = _buffer.substring(match.end).trimLeft();
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
