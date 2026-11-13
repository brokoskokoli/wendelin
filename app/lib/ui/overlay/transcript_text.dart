import 'package:flutter/widgets.dart';

import '../design/design.dart';

/// The user's request in the overlay (WP196): the longer the text, the
/// smaller the font ([WText.transcriptFor]). A step grows back only when the
/// length is 10 % below its threshold, so growing text does not flicker.
/// Only the font size changes; the system text scale still applies.
class TranscriptText extends StatefulWidget {
  /// Shows [text] in quotes.
  const TranscriptText(this.text, {super.key});

  /// The request without quotes.
  final String text;

  @override
  State<TranscriptText> createState() => _TranscriptTextState();
}

class _TranscriptTextState extends State<TranscriptText> {
  late int _step = WText.transcriptStep(widget.text.length);

  @override
  void didUpdateWidget(TranscriptText old) {
    super.didUpdateWidget(old);
    final text = widget.text;
    final raw = WText.transcriptStep(text.length);
    final related = text.startsWith(old.text) || old.text.startsWith(text);
    if (!related) {
      _step = raw; // a different request starts fresh
    } else if (raw > _step) {
      _step = raw;
    } else {
      final settled = WText.transcriptStep(
        text.length / WText.transcriptHysteresis,
      );
      if (settled < _step) _step = settled;
    }
  }

  @override
  Widget build(BuildContext context) =>
      Text('„${widget.text}“', style: WText.transcriptAt(_step));
}
