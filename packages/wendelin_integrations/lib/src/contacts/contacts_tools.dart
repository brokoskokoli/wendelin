import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import 'contacts_ports.dart';

/// Longest SMS text accepted (several SMS parts).
const maxSmsChars = 1000;

/// `contacts__find` (read): name → numbers and mail addresses. Several
/// matches (or several numbers of one contact) are reported as a choice
/// the model must put to the user. The names come from third parties, so
/// the result is untrusted content.
final class ContactsFindTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const ContactsFindTool(this.finder);

  /// Name search.
  final ContactsFinder finder;

  @override
  String get name => 'contacts__find';

  @override
  String get description =>
      'Look up a person in the address book by name. Returns matches with '
      'phone numbers and mail addresses. If "choice_needed" is true there '
      'is more than one match or number: ask the user which one is meant '
      'and never guess. Use the exact "number" from this result for '
      'sms__compose and phone__call.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Name or part of the name, e.g. "Anna" or "Anna Meier".',
      },
    },
    'required': ['query'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('query');
    final matches = await finder.find(query);
    if (matches.isEmpty) {
      return ToolOutcome.text(
        jsonEncode({'matches': <Object>[], 'choice_needed': false}),
        summary: 'Kein Kontakt gefunden',
      );
    }
    final choice = matches.length > 1 || matches.single.phones.length > 1;
    return jsonOutcome(
      {
        'matches': [for (final m in matches) m.toJson()],
        'choice_needed': choice,
        if (choice)
          'hint':
              'Ask the user which contact or number is meant before '
              'writing or calling.',
      },
      summary: matches.length == 1
          ? 'Kontakt ${matches.single.name}'
          : '${matches.length} Kontakte',
    );
  }

  @override
  String describe(ToolArgs args) => 'Kontakt suchen';

  @override
  String get fallbackDescription => 'Kontakt suchen';
}

/// The recipient as shown to the user: the name of the contact who owns
/// the number (looked up, never taken from the model), else the number.
Future<({String name, String number})> recipientOf(
  ContactsFinder finder,
  String raw,
) async {
  final number = cleanPhoneNumber(raw);
  if (number == null) {
    throw const InvalidArgumentsException(
      '„to“ ist keine Telefonnummer. Zuerst contacts__find nutzen und die '
      'Nummer daraus übernehmen.',
    );
  }
  final contact = await finder.byNumber(number);
  return (name: contact?.name ?? number, number: number);
}

/// Preview line of a recipient: `Anna Meier (+49170123)` or just the number.
String recipientLine(String name, String number) =>
    name == number ? number : '$name ($number)';

/// `sms__compose` (external): sends an SMS after the user confirmed the
/// preview (recipient with name and number, editable text). The text that
/// was confirmed is the text that is sent: an edit of the preview wins
/// ([SmsDraftEdits]).
final class SmsComposeTool extends IntegrationTool
    implements
        ConfirmationPreparer,
        AuditArgumentsRedactor,
        FixedConfirmationTool,
        NoNetworkTarget,
        TrustedContentSource {
  /// Creates the tool.
  const SmsComposeTool(this.finder, this.phone, this.edits);

  /// Reverse lookup of the recipient.
  final ContactsFinder finder;

  /// SMS sending.
  final PhonePort phone;

  /// Texts changed in the preview.
  final SmsDraftEdits edits;

  @override
  String get name => 'sms__compose';

  @override
  String get description =>
      'Write an SMS. Wendelin shows the user a preview with the recipient '
      'and the text and sends only after the user confirms; you cannot '
      'confirm for the user. "to" is a phone number, taken from '
      'contacts__find (ask the user if several matches) or dictated by the '
      'user. Do not claim the SMS was sent before the result says so.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'to': {'type': 'string', 'description': 'Phone number of the recipient.'},
      'text': {'type': 'string', 'description': 'Text of the SMS.'},
    },
    'required': ['to', 'text'],
  };

  @override
  RiskLevel get risk => RiskLevel.external;

  @override
  Set<String> get confirmationKeys => const {'sms.sent'};

  ({String to, String text}) _read(ToolArgs args) {
    final text = args.requireString('text').trim();
    if (text.isEmpty) throw const InvalidArgumentsException('„text“ ist leer');
    if (text.length > maxSmsChars) {
      throw const InvalidArgumentsException(
        '„text“ ist zu lang (höchstens $maxSmsChars Zeichen)',
      );
    }
    return (to: args.requireString('to'), text: text);
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final (:to, :text) = _read(args);
    final recipient = await recipientOf(finder, to);
    final confirmed = edits.take(recipient.number, text) ?? text;
    if (confirmed.isEmpty || confirmed.length > maxSmsChars) {
      throw const InvalidArgumentsException(
        'Der geänderte Text ist leer oder zu lang (höchstens '
        '$maxSmsChars Zeichen)',
      );
    }
    if (!await phone.canSendSms()) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Wendelin darf keine SMS senden. Die Berechtigung lässt sich in den '
        'Einstellungen der Integration „Kontakte & Telefon“ erteilen.',
      );
    }
    await phone.sendSms(recipient.number, confirmed);
    return ToolOutcome.text(
      'Die SMS an ${recipient.name} wurde gesendet.',
      summary: 'SMS an ${recipient.name} gesendet',
      fixed: ConfirmationSentence('sms.sent', {'name': recipient.name}),
    );
  }

  @override
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final (:to, :text) = _read(ToolArgs(args));
    final r = await recipientOf(finder, to);
    return 'SMS an ${recipientLine(r.name, r.number)}\n$text';
  }

  @override
  Future<String> redactedArguments(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final r = await recipientOf(finder, ToolArgs(args).requireString('to'));
    return jsonEncode({'recipient': r.name});
  }

  @override
  String describe(ToolArgs args) {
    final (:to, :text) = _read(args);
    return 'SMS an ${cleanPhoneNumber(to) ?? to}\n$text';
  }

  @override
  String get fallbackDescription => 'SMS senden';
}

/// `phone__call` (external): calls a number after the user confirmed
/// (name and number shown). Without `CALL_PHONE` the dialer opens instead.
final class PhoneCallTool extends IntegrationTool
    implements
        ConfirmationPreparer,
        AuditArgumentsRedactor,
        FixedConfirmationTool,
        NoNetworkTarget,
        TrustedContentSource {
  /// Creates the tool.
  const PhoneCallTool(this.finder, this.phone);

  /// Reverse lookup of the recipient.
  final ContactsFinder finder;

  /// Calls.
  final PhonePort phone;

  @override
  String get name => 'phone__call';

  @override
  String get description =>
      'Call a phone number. Wendelin shows the user the name and number and '
      'calls only after the user confirms; you cannot confirm for the '
      'user. "to" is a phone number, taken from contacts__find (ask the '
      'user if several matches) or dictated by the user.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'to': {'type': 'string', 'description': 'Phone number to call.'},
    },
    'required': ['to'],
  };

  @override
  RiskLevel get risk => RiskLevel.external;

  @override
  Set<String> get confirmationKeys => const {'call.started'};

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final r = await recipientOf(finder, args.requireString('to'));
    final placement = await phone.call(r.number);
    return switch (placement) {
      CallPlacement.direct => ToolOutcome.text(
        'Der Anruf bei ${r.name} wurde gestartet.',
        summary: 'Anruf bei ${r.name}',
        fixed: ConfirmationSentence('call.started', {'name': r.name}),
      ),
      CallPlacement.dialer => ToolOutcome.text(
        'Der Wählbildschirm mit der Nummer von ${r.name} ist geöffnet; der '
        'Nutzer startet den Anruf selbst.',
        summary: 'Wählbildschirm für ${r.name}',
      ),
    };
  }

  @override
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final r = await recipientOf(finder, ToolArgs(args).requireString('to'));
    return 'Anrufen: ${recipientLine(r.name, r.number)}';
  }

  @override
  Future<String> redactedArguments(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final r = await recipientOf(finder, ToolArgs(args).requireString('to'));
    return jsonEncode({'recipient': r.name});
  }

  @override
  String describe(ToolArgs args) {
    final to = args.requireString('to');
    return 'Anrufen: ${cleanPhoneNumber(to) ?? to}';
  }

  @override
  String get fallbackDescription => 'Anrufen';
}
