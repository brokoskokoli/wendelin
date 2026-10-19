import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

export 'channels.dart' show contactsChannelName;

/// [ContactsPort] and [PhonePort] over the Kotlin `ContactsChannel`
/// (ContactsContract, `SmsManager`, `ACTION_CALL`/`ACTION_DIAL`).
///
/// The channel never asks the user; the tools confirm first.
final class ChannelContactsPort implements ContactsPort, PhonePort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelContactsPort({
    this._channel = const MethodChannel(contactsChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> hasPermission() async =>
      await _call<bool>('hasPermission') ?? false;

  /// Asks for the address book, SMS and phone permission together (when the
  /// integration is switched on). `true` if the address book may be read;
  /// SMS and calls degrade on their own (error, dialer).
  Future<bool> requestPermission() async =>
      await _call<bool>('requestPermission') ?? false;

  @override
  Future<bool> canSendSms() async => await _call<bool>('canSendSms') ?? false;

  @override
  Future<List<ContactEntry>> all() async {
    final rows = await _call<List<Object?>>('all') ?? const [];
    return [
      for (final row in rows.whereType<Map<Object?, Object?>>())
        ContactEntry(
          name: row['name']! as String,
          phones: [
            for (final p
                in (row['phones'] as List<Object?>? ?? const [])
                    .whereType<Map<Object?, Object?>>())
              ContactPhone(
                p['number']! as String,
                label: p['label'] as String? ?? '',
              ),
          ],
          emails: [
            for (final e in (row['emails'] as List<Object?>? ?? const []))
              e! as String,
          ],
        ),
    ];
  }

  @override
  Future<void> sendSms(String number, String text) =>
      _call<void>('sendSms', {'number': number, 'text': text});

  @override
  Future<CallPlacement> call(String number) async {
    final how = await _call<String>('call', {'number': number});
    return how == 'direct' ? CallPlacement.direct : CallPlacement.dialer;
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'permissionDenied' => const PortException(
          PortErrorKind.permissionDenied,
          'Dafür fehlt die Berechtigung. Sie lässt sich in den Einstellungen '
          'der Integration „Kontakte & Telefon“ erteilen.',
        ),
        'unsupported' => const PortException(
          PortErrorKind.unsupported,
          'Dieses Gerät kann keine SMS senden.',
        ),
        'bad_args' => const PortException(
          PortErrorKind.rejected,
          'Ungültige Nummer oder leerer Text.',
        ),
        _ => const PortException(
          PortErrorKind.failed,
          'Das hat nicht geklappt (Telefon oder Kontakte nicht erreichbar).',
        ),
      };
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Kontakte und Telefon gibt es hier nicht.',
      );
    }
  }
}
