import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Trenner im Verlauf, wenn an ein anderes Modell übergeben wurde
/// (z. B. „an Claude Sonnet übergeben“).
class EscalationDivider extends StatelessWidget {
  /// Erstellt einen Trenner mit [label].
  const EscalationDivider(this.label, {super.key});

  /// Text in der Mitte.
  final String label;

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: ExcludeSemantics(
        child: ColoredBox(
          color: WColors.line,
          child: SizedBox(height: WSize.divider),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        spacing: WSpace.s,
        children: [
          line,
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * WSize.bubbleMaxFraction,
            ),
            child: Text(
              label,
              style: WText.caption,
              textAlign: TextAlign.center,
            ),
          ),
          line,
        ],
      ),
    );
  }
}
