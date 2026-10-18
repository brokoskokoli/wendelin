import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../di/voice_settings_providers.dart';

/// Whether the one-time question „Weiter zuhören?“ is shown now.
final conversationOfferProvider = NotifierProvider<ConversationOffer, bool>(
  ConversationOffer.new,
);

/// The one-time question after the first spoken answer that a follow-up
/// would have suited. „Due“ is stored (`conversationOfferPending`), because
/// the overlay runs in its own engine and the main screen shows the card
/// later. The answer is stored too (`conversationMode`, `conversationAsked`);
/// once answered – or once the setting was chosen in the settings or the
/// onboarding – the question never comes again.
final class ConversationOffer extends Notifier<bool> {
  @override
  bool build() {
    final s = ref.watch(voiceSettingsProvider).value;
    return s != null && s.conversationOfferPending && !s.conversationAsked;
  }

  /// Marks the question as due, unless it was answered before.
  Future<void> offer() async {
    final s = await ref.read(voiceSettingsProvider.future);
    if (!ref.mounted || s.conversationAsked || s.conversationOfferPending) {
      return;
    }
    await ref
        .read(voiceSettingsProvider.notifier)
        .change((s) => s.copyWith(conversationOfferPending: true));
  }

  /// Stores the answer and never asks again.
  Future<void> answer({required bool yes}) async {
    await ref
        .read(voiceSettingsProvider.notifier)
        .change(
          (s) => s.copyWith(
            conversationMode: yes,
            conversationAsked: true,
            conversationOfferPending: false,
          ),
        );
  }
}

/// Remembers what was spoken of the current voice request and decides
/// when a request ended with an answer after which a follow-up would have
/// helped ([followUpUseful]).
final class SpokenAnswerTracker {
  String? _last;
  DateTime? _lastAnswerAt;

  /// A sentence of the answer is being spoken.
  void spoke(String sentence) => _last = sentence;

  /// The request was cancelled (tap, „Stopp“): nothing to offer after it.
  void cancelled() => _last = null;

  /// The request is over at [now]. Returns whether the question should be
  /// offered. A request without a spoken answer neither counts nor offers.
  bool finished(DateTime now) {
    final last = _last;
    _last = null;
    if (last == null) return false;
    final previous = _lastAnswerAt;
    _lastAnswerAt = now;
    return followUpUseful(
      lastSentence: last,
      sinceLastAnswer: previous == null ? null : now.difference(previous),
    );
  }
}
