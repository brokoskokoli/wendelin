import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Antwort des Assistenten als ruhiger Fließtext (ohne Blase), optional mit
/// einem Link am Ende (z. B. „Notiz öffnen“).
class AssistantText extends StatefulWidget {
  /// Erstellt einen Antworttext.
  const AssistantText(
    this.text, {
    super.key,
    this.linkLabel,
    this.onLinkTap,
    this.large = false,
  });

  /// Antworttext.
  final String text;

  /// Beschriftung des Links; ohne [onLinkTap] wird kein Link gezeigt.
  final String? linkLabel;

  /// Aktion des Links.
  final VoidCallback? onLinkTap;

  /// 18 statt 16 (Antwort im Overlay).
  final bool large;

  @override
  State<AssistantText> createState() => _AssistantTextState();
}

class _AssistantTextState extends State<AssistantText> {
  final _recognizer = TapGestureRecognizer();

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.large ? WText.answer : WText.chatAnswer;
    final link = widget.linkLabel;
    if (link == null || widget.onLinkTap == null) {
      return Text(widget.text, style: style);
    }
    _recognizer.onTap = widget.onLinkTap;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '${widget.text} '),
          TextSpan(
            text: link,
            recognizer: _recognizer,
            style: const TextStyle(
              color: WColors.link,
              decoration: TextDecoration.underline,
              decorationColor: WColors.link,
            ),
          ),
        ],
      ),
    );
  }
}
