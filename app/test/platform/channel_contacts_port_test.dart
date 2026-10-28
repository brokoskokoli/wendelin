import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_contacts_port.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Stands in for `ContactsChannel.kt`: address book, permissions, SMS and
/// calls; [errorCode] makes every call fail with that code.
final class _FakeContactsChannel {
  bool permission = true;
  bool smsPermission = true;
  String callHow = 'direct';
  String? errorCode;
  final List<MethodCall> calls = [];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (errorCode case final code?) throw PlatformException(code: code);
    switch (call.method) {
      case 'hasPermission':
        return permission;
      case 'requestPermission':
        return permission;
      case 'canSendSms':
        return smsPermission;
      case 'all':
        return [
          {
            'name': 'Anna Meier',
            'phones': [
              {'number': '+49 170 1234567', 'label': 'Mobil'},
              {'number': '030 222'},
            ],
            'emails': ['anna@example.org'],
            'addresses': [
              {
                'address': 'Musterstraße 1, 12345 Musterstadt',
                'label': 'Privat',
              },
              {'address': 'Beispielweg 2, 54321 Beispielstadt'},
            ],
            'birthday': '1985-03-14',
            'organization': 'Muster GmbH',
          },
          {'name': 'Ben'},
        ];
      case 'sendSms':
      case 'call':
        return call.method == 'call' ? callHow : null;
    }
    throw MissingPluginException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(contactsChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeContactsChannel platform;

  setUp(() {
    platform = _FakeContactsChannel();
    messenger.setMockMethodCallHandler(channel, platform.handle);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const port = ChannelContactsPort();

  test('all() liest Namen, Nummern mit Etikett und Mails', () async {
    final all = await port.all();
    expect(all.map((c) => c.name), ['Anna Meier', 'Ben']);
    expect(all.first.phones.map((p) => p.number), [
      '+49 170 1234567',
      '030 222',
    ]);
    expect(all.first.phones.first.label, 'Mobil');
    expect(all.first.phones.last.label, isEmpty);
    expect(all.first.emails, ['anna@example.org']);
    expect(all.last.phones, isEmpty);
  });

  test('all(): ohne Angabe fragt der Kanal Telefon und Mail', () async {
    await port.all();
    final args = platform.calls.single.arguments as Map<Object?, Object?>;
    expect(args['fields'], unorderedEquals(['phone', 'email']));
  });

  test('all(fields): Feldnamen gehen an den Kanal, Adresse, Geburtstag und '
      'Firma kommen zurück', () async {
    final all = await port.all(
      fields: {
        ContactField.address,
        ContactField.birthday,
        ContactField.organization,
      },
    );
    final args = platform.calls.single.arguments as Map<Object?, Object?>;
    expect(
      args['fields'],
      unorderedEquals(['address', 'birthday', 'organization']),
    );
    final anna = all.first;
    expect(anna.addresses.map((a) => a.address), [
      'Musterstraße 1, 12345 Musterstadt',
      'Beispielweg 2, 54321 Beispielstadt',
    ]);
    expect(anna.addresses.map((a) => a.label), ['Privat', '']);
    expect(anna.birthday, '1985-03-14');
    expect(anna.organization, 'Muster GmbH');
    expect(all.last.addresses, isEmpty);
    expect(all.last.birthday, isNull);
  });

  test('Berechtigungen', () async {
    expect(await port.hasPermission(), isTrue);
    expect(await port.requestPermission(), isTrue);
    platform
      ..permission = false
      ..smsPermission = false;
    expect(await port.hasPermission(), isFalse);
    expect(await port.canSendSms(), isFalse);
  });

  test('sendSms übergibt Nummer und Text', () async {
    await port.sendSms('+491701234567', 'Hallo');
    expect(platform.calls.single.method, 'sendSms');
    expect(platform.calls.single.arguments, {
      'number': '+491701234567',
      'text': 'Hallo',
    });
  });

  test('call: direkt oder Wählbildschirm', () async {
    expect(await port.call('0171111'), CallPlacement.direct);
    platform.callHow = 'dialer';
    expect(await port.call('0171111'), CallPlacement.dialer);
    expect(platform.calls.last.arguments, {'number': '0171111'});
  });

  for (final (code, kind) in [
    ('permissionDenied', PortErrorKind.permissionDenied),
    ('unsupported', PortErrorKind.unsupported),
    ('bad_args', PortErrorKind.rejected),
    ('failed', PortErrorKind.failed),
    ('irgendwas', PortErrorKind.failed),
  ]) {
    test('Fehlercode $code wird zu $kind', () async {
      platform.errorCode = code;
      await expectLater(
        port.sendSms('1', 'x'),
        throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind)),
      );
    });
  }

  test('ohne Plugin: unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      port.all(),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.unsupported,
        ),
      ),
    );
  });
}
