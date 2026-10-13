import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Text field that highlights `{placeholder}`s: known arguments in the
/// accent colour, unknown ones in the error colour.
class PlaceholderTextController extends TextEditingController {
  /// Creates the controller; [known] gives the argument names.
  PlaceholderTextController({super.text, required this.known});

  /// Names of the arguments.
  final Set<String> Function() known;

  static final _placeholder = RegExp(r'\{([^{}]*)\}');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final names = known();
    final children = <TextSpan>[];
    var last = 0;
    for (final m in _placeholder.allMatches(text)) {
      if (m.start > last) {
        children.add(TextSpan(text: text.substring(last, m.start)));
      }
      final ok = names.contains(m[1]);
      children.add(
        TextSpan(
          text: m[0],
          style: TextStyle(
            color: ok ? WColors.accentLight : WColors.error,
            fontWeight: FontWeight.w600,
          ),
          semanticsLabel: ok ? null : '${m[0]} unbekannt',
        ),
      );
      last = m.end;
    }
    if (last < text.length) children.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: children);
  }
}
