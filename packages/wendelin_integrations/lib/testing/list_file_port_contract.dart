import 'dart:async';

import 'package:test/test.dart';

import '../src/common/port_exception.dart';
import '../src/lists/lists.dart';

/// What [listFilePortContract] needs: the port, a way to get a handle for
/// a file that does **not** exist yet (Android: a new document name inside
/// a granted SAF folder), and optional cleanup of created files.
typedef ListFileContractSetup = ({
  ListFilePort port,
  FutureOr<String> Function() newHandle,
  FutureOr<void> Function(String handle)? delete,
});

/// Creates the setup for one check.
typedef ListFilePortFactory = FutureOr<ListFileContractSetup> Function();

/// Names of the checks in [listFilePortContractChecks].
abstract final class ListFilePortChecks {
  /// A new handle does not exist and cannot be read.
  static const missing = 'neue Datei: exists false, read notFound';

  /// write creates the file.
  static const create = 'write legt die Datei an';

  /// Content survives character for character.
  static const exact =
      'Inhalt bleibt zeichengenau (CRLF, ohne Schlusszeilenumbruch, Unicode, '
      'BOM, Frontmatter)';

  /// A shorter write truncates (no leftovers of the old content).
  static const truncate = 'kürzerer Inhalt überschreibt vollständig';

  /// Empty content.
  static const empty = 'leerer Inhalt';

  /// Large content (300 KB).
  static const large = 'großer Inhalt (300 KB)';
}

/// Reusable contract suite for every [ListFilePort] (`FakeListFilePort`,
/// the app's SAF port); registers one test per entry of
/// [listFilePortContractChecks].
void listFilePortContract(
  ListFilePortFactory create, {
  String name = 'ListFilePort',
}) {
  group('$name erfüllt den ListFilePort-Vertrag', () {
    listFilePortContractChecks(create).forEach(test);
  });
}

/// The checks of [listFilePortContract] by name ([ListFilePortChecks]).
Map<String, Future<void> Function()> listFilePortContractChecks(
  ListFilePortFactory create,
) {
  Future<void> withFile(
    Future<void> Function(ListFilePort port, String handle) body,
  ) async {
    final s = await create();
    final handle = await s.newHandle();
    try {
      await body(s.port, handle);
    } finally {
      if (s.delete != null && await s.port.exists(handle)) {
        await s.delete!(handle);
      }
    }
  }

  Future<void> roundTrip(ListFilePort p, String h, String content) async {
    await p.write(h, content);
    final back = await p.read(h);
    expect(back.length, content.length, reason: 'Länge');
    expect(back, content);
  }

  return {
    ListFilePortChecks.missing: () => withFile((p, h) async {
      expect(await p.exists(h), isFalse);
      await expectLater(
        p.read(h),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.notFound,
          ),
        ),
      );
    }),
    ListFilePortChecks.create: () => withFile((p, h) async {
      await p.write(h, '- [ ] Milch\n');
      expect(await p.exists(h), isTrue);
      expect(await p.read(h), '- [ ] Milch\n');
    }),
    ListFilePortChecks.exact: () => withFile((p, h) async {
      await roundTrip(
        p,
        h,
        '﻿---\r\ntags: [liste]\r\n---\r\n# Einkaufen\r\n'
        '- [ ] Grüße ‚Milch‘ 🥛\r\n\t- [x] Unterpunkt\r\n\r\nEnde ohne Umbruch',
      );
      await roundTrip(p, h, 'nur\nLF\n\n');
      await roundTrip(p, h, 'altes\rMac\r');
    }),
    ListFilePortChecks.truncate: () => withFile((p, h) async {
      await p.write(h, '- [ ] ${'x' * 500}\n- [ ] zweiter\n');
      await roundTrip(p, h, '- [ ] kurz\n');
    }),
    ListFilePortChecks.empty: () => withFile((p, h) async {
      await p.write(h, 'etwas');
      await roundTrip(p, h, '');
      expect(await p.exists(h), isTrue);
    }),
    ListFilePortChecks.large: () => withFile((p, h) async {
      final big = List.generate(
        10000,
        (i) => '- [ ] Eintrag $i äöü',
      ).join('\n');
      await roundTrip(p, h, big);
    }),
  };
}
