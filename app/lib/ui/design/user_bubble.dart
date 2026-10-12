import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Nachricht des Nutzers: rechtsbündige Blase (max. 80 % Breite),
/// `surfaceRaised`, Ecke unten rechts spitz.
class UserBubble extends StatelessWidget {
  /// Erstellt eine Nutzer-Blase.
  const UserBubble(this.text, {super.key});

  /// Nachrichtentext.
  final String text;

  static const _padding = EdgeInsets.symmetric(
    horizontal: WSpace.m14,
    vertical: WSpace.m,
  );

  @override
  Widget build(BuildContext context) {
    // Wie im Entwurf (CSS content-box): 80 % gelten für den Text, der
    // Innenabstand kommt hinzu.
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                constraints.maxWidth * WSize.bubbleMaxFraction +
                _padding.horizontal,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: WColors.surfaceRaised,
              borderRadius: BorderRadiusDirectional.only(
                topStart: Radius.circular(WRadius.cardLarge),
                topEnd: Radius.circular(WRadius.cardLarge),
                bottomStart: Radius.circular(WRadius.cardLarge),
                bottomEnd: Radius.circular(WRadius.tail),
              ),
            ),
            child: Padding(
              padding: _padding,
              child: Text(text, style: WText.bubble),
            ),
          ),
        ),
      ),
    );
  }
}
