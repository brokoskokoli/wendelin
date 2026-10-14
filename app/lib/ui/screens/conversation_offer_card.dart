import 'package:flutter/material.dart';

import '../../voice/conversation_offer.dart';
import '../design/design.dart';

/// The one-time question after the first spoken answer: „Soll ich nach
/// meinen Antworten standardmäßig weiter zuhören?“ with Ja/Nein and the
/// note that the settings change it any time (K23 d, M4 decision 2).
class ConversationOfferCard extends StatelessWidget {
  /// Creates the card; [onAnswer] gets the choice.
  const ConversationOfferCard({super.key, required this.onAnswer});

  /// Called with `true` for „Ja“ and `false` for „Nein“.
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) => SectionCard(
    dividers: false,
    spacing: WSpace.m,
    padding: const EdgeInsets.all(WSpace.l18),
    children: [
      Text(conversationOfferQuestion, style: WText.label),
      Text(conversationOfferHint, style: WText.intro),
      Row(
        spacing: WSpace.s,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => onAnswer(false),
              child: const Text('Nein'),
            ),
          ),
          Expanded(
            child: FilledButton(
              onPressed: () => onAnswer(true),
              child: const Text('Ja'),
            ),
          ),
        ],
      ),
    ],
  );
}
