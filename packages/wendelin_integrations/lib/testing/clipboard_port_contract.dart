import 'dart:async';

import 'package:test/test.dart';

import '../src/clipboard/clipboard.dart';

/// Creates the [ClipboardPort] under test (app in the foreground).
typedef ClipboardPortFactory = FutureOr<ClipboardPort> Function();

/// Names of the checks in [clipboardPortContractChecks].
abstract final class ClipboardPortChecks {
  /// write then read returns the same text.
  static const roundTrip = 'write dann read liefert denselben Text';

  /// Unicode, surrounding whitespace, line breaks and tabs survive.
  static const unicode =
      'Unicode, Leerraum und Zeilenumbrüche bleiben erhalten';

  /// The last write wins.
  static const lastWins = 'letzter write gewinnt';

  /// Writing an empty text empties the clipboard.
  static const empty = 'leerer Text leert die Zwischenablage';
}

/// Reusable contract suite for every [ClipboardPort] implementation;
/// registers one test per entry of [clipboardPortContractChecks].
///
/// Overwrites the clipboard; a previous text content is restored after
/// each check.
void clipboardPortContract(
  ClipboardPortFactory create, {
  String name = 'ClipboardPort',
}) {
  group('$name erfüllt den ClipboardPort-Vertrag', () {
    clipboardPortContractChecks(create).forEach(test);
  });
}

/// The checks of [clipboardPortContract] by name ([ClipboardPortChecks]).
Map<String, Future<void> Function()> clipboardPortContractChecks(
  ClipboardPortFactory create,
) {
  Future<void> withPort(Future<void> Function(ClipboardPort p) body) async {
    final port = await create();
    final saved = await port.read();
    try {
      await body(port);
    } finally {
      if (saved != null) await port.write(saved);
    }
  }

  return {
    ClipboardPortChecks.roundTrip: () => withPort((p) async {
      await p.write('Wendelin Vertrag 1');
      expect(await p.read(), 'Wendelin Vertrag 1');
    }),
    ClipboardPortChecks.unicode: () => withPort((p) async {
      const text = '  Grüße ‚Tauchen‘ 🌊\nZeile 2\tTab\n';
      await p.write(text);
      expect(await p.read(), text);
    }),
    ClipboardPortChecks.lastWins: () => withPort((p) async {
      await p.write('erst');
      await p.write('dann');
      expect(await p.read(), 'dann');
    }),
    ClipboardPortChecks.empty: () => withPort((p) async {
      await p.write('etwas');
      await p.write('');
      expect(await p.read(), anyOf(isNull, isEmpty));
    }),
  };
}
