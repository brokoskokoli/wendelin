import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import '../maps/navigation_apps.dart';
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
      'Look up a person in the address book by name. Returns phones and mail '
      'addresses, or only the "fields" you ask for ("address" only if the '
      'user wants to know it; to navigate use contacts__navigate). If '
      '"choice_needed" is true, ask which one is meant, never guess. Use the '
      'exact "number" for sms__compose.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Name or part of the name, e.g. "Anna" or "Anna Meier".',
      },
      'fields': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': ['phone', 'email', 'address', 'birthday', 'organization'],
        },
        'minItems': 1,
        'description':
            'Data to return, only what is needed. Default: phone and email. '
            'Empty list = none stored.',
      },
    },
    'required': ['query'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('query');
    final fields = _requestedFields(args);
    final matches = await finder.find(
      query,
      fields: fields ?? defaultContactFields,
    );
    if (matches.isEmpty) {
      return ToolOutcome.text(
        jsonEncode({'matches': <Object>[], 'choice_needed': false}),
        summary: 'Kein Kontakt gefunden',
      );
    }
    final shown = fields ?? defaultContactFields;
    final choice =
        matches.length > 1 ||
        (shown.contains(ContactField.phone) &&
            matches.first.phones.length > 1) ||
        (shown.contains(ContactField.address) &&
            matches.first.addresses.length > 1);
    return jsonOutcome(
      {
        'matches': [
          for (final m in matches)
            fields == null ? m.toJson() : m.toJsonFor(fields),
        ],
        'choice_needed': choice,
        if (choice)
          'hint':
              'Ask the user which contact, number or address is meant '
              'before writing, calling or navigating.',
      },
      summary: matches.length == 1
          ? 'Kontakt ${matches.single.name}'
          : '${matches.length} Kontakte',
    );
  }

  /// The `fields` argument; `null` if absent. Unknown names and an empty
  /// list are refused (nothing is ignored silently).
  static Set<ContactField>? _requestedFields(ToolArgs args) {
    final raw = args.optStringList('fields');
    if (raw == null) return null;
    const allowed = 'phone, email, address, birthday, organization';
    if (raw.isEmpty) {
      throw const InvalidArgumentsException(
        '„fields“ darf nicht leer sein. Erlaubt: $allowed',
      );
    }
    final fields = <ContactField>{};
    for (final name in raw) {
      final f = ContactField.byName(name);
      if (f == null) {
        throw InvalidArgumentsException(
          'Unbekanntes Feld „$name“ in „fields“. Erlaubt: $allowed',
        );
      }
      fields.add(f);
    }
    return fields;
  }

  @override
  String describe(ToolArgs args) => 'Kontakt suchen';

  @override
  String get fallbackDescription => 'Kontakt suchen';
}

/// `contacts__navigate` (write): looks up a contact and starts navigation to
/// its postal address in one step (WP164 C). The address never goes to the
/// model: it only gets a status (`ok`, `no_contact`, `no_address`,
/// `choice_needed` with contact names or address labels,
/// `app_unavailable`). The address is not in a result, summary, error,
/// confirmation text or audit entry either. The navigation app is chosen
/// like for `maps__navigate` ([NavigationStarter]).
final class ContactsNavigateTool extends IntegrationTool
    implements
        AuditArgumentsRedactor,
        ConditionalTool,
        FixedConfirmationTool,
        NoNetworkTarget,
        TrustedContentSource,
        WorksOnlyUnlocked {
  /// Creates the tool.
  const ContactsNavigateTool(this.finder, this.starter);

  /// Name search.
  final ContactsFinder finder;

  /// App choice and launch, shared with `maps__navigate`.
  final NavigationStarter starter;

  @override
  String get name => 'contacts__navigate';

  @override
  String get description =>
      'Navigate to a person from the address book ("navigate to Anna"). '
      'You never see the address; the result is only a status: ok (done, '
      'say nothing more), no_contact, no_address, app_unavailable or '
      'choice_needed ("contacts"/"address_labels": ask the user, then call '
      'again). "app" only if the user names one.';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': <String, Object?>{
      'name': {
        'type': 'string',
        'description': 'Name or part of the name, e.g. "Anna Meier".',
      },
      'address_label': {
        'type': 'string',
        'description':
            'Which address if the contact has several, e.g. "Privat" or '
            '"Arbeit" (as listed in a choice_needed answer).',
      },
      'app': {
        'type': 'string',
        if (starter.apps.active.isNotEmpty)
          'enum': [
            for (final a in NavigationApp.values)
              if (starter.apps.active.contains(a)) a.id,
          ],
        'description': 'Navigation app; default: the one set in the settings.',
      },
    },
    'required': <String>['name'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  /// Without any usable navigation app the tool stays out of the catalog.
  @override
  bool get offered => starter.apps.active.isNotEmpty;

  @override
  Set<String> get confirmationKeys => const {'navigation.started'};

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('name').trim();
    if (query.isEmpty) throw const InvalidArgumentsException('„name“ fehlt');
    final label = args.optString('address_label')?.trim();
    final requestedApp = args.optString('app');

    final matches = await finder.find(
      query,
      fields: const {ContactField.address},
    );
    if (matches.isEmpty) return _status('no_contact', 'Kein Kontakt gefunden');
    if (matches.length > 1) {
      return _status(
        'choice_needed',
        'Mehrere Kontakte',
        extra: {
          'contacts': [for (final m in matches) m.name],
        },
      );
    }
    final contact = matches.single;
    final addresses = [
      for (final a in contact.addresses)
        if (_oneLine(a.address).isNotEmpty) a,
    ];
    if (addresses.isEmpty) {
      return _status('no_address', 'Keine Adresse für ${contact.name}');
    }
    final labels = [
      for (var i = 0; i < addresses.length; i++)
        // Unlabeled addresses are told apart as „Adresse 1“, „Adresse 2“.
        addresses[i].label.trim().isNotEmpty
            ? addresses[i].label.trim()
            : 'Adresse ${i + 1}',
    ];
    final index = _pick(labels, label);
    if (index == null) {
      return _status(
        'choice_needed',
        'Adresse wählen',
        extra: {'address_labels': labels},
      );
    }
    final destination = _oneLine(addresses[index].address);
    if (destination.length > 200) {
      return _status('no_address', 'Keine nutzbare Adresse');
    }
    final (:app, :unavailable) = await starter.resolve(requestedApp);
    if (app == null) {
      return _status('app_unavailable', unavailable!.summary);
    }
    try {
      await starter.launch(app, destination);
    } on PortException {
      // The message could name the target: only the status goes out.
      return _status('app_unavailable', 'Navigations-App nicht verfügbar');
    }
    return ToolOutcome.text(
      jsonEncode({'status': 'ok'}),
      summary: 'Navigation zu ${contact.name} gestartet',
      fixed: ConfirmationSentence('navigation.started', {'name': contact.name}),
    );
  }

  /// The index of the address meant by [wanted] among [labels]; `null` if
  /// the user has to choose (several addresses and no unique label match).
  static int? _pick(List<String> labels, String? wanted) {
    if (wanted == null || wanted.isEmpty) {
      return labels.length == 1 ? 0 : null;
    }
    final key = foldForMatch(wanted);
    final hits = [
      for (var i = 0; i < labels.length; i++)
        if (foldForMatch(labels[i]) == key) i,
    ];
    return hits.length == 1 ? hits.single : null;
  }

  /// A formatted address on one line (the address book stores line breaks).
  static String _oneLine(String address) =>
      address.trim().replaceAll(RegExp(r'\s*[\r\n]+\s*'), ', ');

  ToolOutcome _status(
    String status,
    String summary, {
    Map<String, Object?> extra = const {},
  }) => ToolOutcome.text(
    jsonEncode({'status': status, ...extra}),
    summary: summary,
  );

  @override
  Future<String> redactedArguments(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => jsonEncode({'contact': ToolArgs(args).optString('name') ?? ''});

  // The audit log stores confirmation texts: no address in it.
  @override
  String describe(ToolArgs args) =>
      'Navigation zu ${args.requireString('name')} starten';

  @override
  String get fallbackDescription => 'Navigation zu einem Kontakt starten';
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
        WorksOnlyUnlocked,
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
