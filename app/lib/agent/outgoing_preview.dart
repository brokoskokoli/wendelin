import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/contacts.dart';

import 'conversation_state.dart';

/// What an outgoing action does.
enum OutgoingKind {
  /// `sms__compose`.
  sms('sms__compose'),

  /// `phone__call`.
  call('phone__call');

  const OutgoingKind(this.tool);

  /// Tool name.
  final String tool;
}

/// The preview of an `sms__compose` or `phone__call` confirmation (WP85):
/// who (name from the address book and number) and, for an SMS, the text.
/// Both the confirmation card and the spoken question are built from it, so
/// what is read aloud is what is shown.
final class OutgoingPreview {
  const OutgoingPreview({
    required this.kind,
    required this.name,
    required this.number,
    this.text = '',
  });

  /// SMS or call.
  final OutgoingKind kind;

  /// Name from the address book, or the number if the contact is unknown.
  final String name;

  /// The cleaned number.
  final String number;

  /// The SMS text as the model wrote it (trimmed); empty for a call.
  final String text;

  /// Whether the contact is known (the name differs from the number).
  bool get known => name != number;

  /// The preview of the confirmation of [call] with the card text
  /// [description] (`SMS an Name (Nummer)\nText` or `Anrufen: Name
  /// (Nummer)`); `null` for any other tool or unusable arguments.
  static OutgoingPreview? of(ToolCallBlock call, String description) {
    final kind = switch (call.name) {
      'sms__compose' => OutgoingKind.sms,
      'phone__call' => OutgoingKind.call,
      _ => null,
    };
    if (kind == null) return null;
    final Object? args;
    try {
      args = jsonDecode(call.argumentsJson);
    } on FormatException {
      return null;
    }
    if (args is! Map<String, Object?>) return null;
    final number = switch (args['to']) {
      final String to => cleanPhoneNumber(to),
      _ => null,
    };
    if (number == null) return null;
    final text = kind == OutgoingKind.sms
        ? (args['text'] is String ? (args['text']! as String).trim() : '')
        : '';
    if (kind == OutgoingKind.sms && text.isEmpty) return null;
    final first = description.split('\n').first;
    final who = first.replaceFirst(RegExp(r'^(SMS an |Anrufen: )'), '').trim();
    final suffix = ' ($number)';
    final name = who.endsWith(suffix)
        ? who.substring(0, who.length - suffix.length)
        : (who.isEmpty ? number : who);
    return OutgoingPreview(kind: kind, name: name, number: number, text: text);
  }
}

/// The preview belonging to an open [question], if it asks for an SMS or a
/// call.
OutgoingPreview? outgoingPreviewOf(PendingQuestion? question) =>
    switch (question) {
      ToolQuestion(:final event) => OutgoingPreview.of(
        event.call,
        event.description,
      ),
      _ => null,
    };
