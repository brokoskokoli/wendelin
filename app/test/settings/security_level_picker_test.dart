// WP154: Auswahl der Sicherheitsstufe A-D (Widget-Test, Golden nur macOS).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/security_level_picker.dart';
import 'package:wendelin/ui/settings/settings_page.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart' show goldenKey;
import 'onboarding_settings_goldens_test.dart' show pumpGoldenScreen;

/// A picker whose state lives in the test, like in the real screens.
class _Host extends StatefulWidget {
  const _Host({
    this.start = SecurityLevel.c,
    this.base = SecurityLevel.c,
    this.warn = const {},
    required this.log,
  });

  final SecurityLevel start;
  final SecurityLevel base;
  final Set<SecurityLevel> warn;
  final List<SecurityLevel?> log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late SecurityLevel _level = widget.start;
  bool _isDefault = true;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Test',
    children: [
      SectionCard(
        children: [
          SettingsRow(title: 'Küche Deckenlicht', detail: 'Küche'),
          SecurityLevelPicker(
            idKey: 'x',
            name: 'Küche Deckenlicht',
            level: _level,
            isDefault: _isDefault,
            warnLevels: widget.warn,
            warnMessage: 'Hinweis-Text',
            onChanged: (l) => setState(() {
              widget.log.add(l);
              _level = l ?? widget.base;
              _isDefault = l == null;
            }),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('eingeklappt: nur eine Zeile, Wahl klappt auf und speichert', (
    tester,
  ) async {
    final log = <SecurityLevel?>[];
    await tester.pumpWidget(TestEnv().app(home: _Host(log: log)));
    await tester.pumpAndSettle();
    expect(find.text('Details · Stufe C · Standard'), findsOneWidget);
    expect(find.byKey(const ValueKey('level_x_a')), findsNothing);
    expect(find.byKey(const ValueKey('levelRestore_x')), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsNothing);

    await tester.tap(find.byKey(const ValueKey('levelDetails_x')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    for (final l in ['a', 'b', 'c', 'd']) {
      expect(find.byKey(ValueKey('level_x_$l')), findsOneWidget);
    }
    expect(find.textContaining('A · Immer, auch bei gesperrtem'), findsOne);
    expect(find.textContaining('D · Entsperrt und mit Bestätigung'), findsOne);

    // Gleiche Stufe wählen ändert nichts.
    await tester.tap(find.byKey(const ValueKey('level_x_c')));
    await tester.pumpAndSettle();
    expect(log, isEmpty);

    await tester.tap(find.byKey(const ValueKey('level_x_d')));
    await tester.pumpAndSettle();
    expect(log, [SecurityLevel.d]);
    expect(find.text('Details · Stufe D · geändert'), findsOneWidget);

    // Standard wiederherstellen (`null`) und der Knopf verschwindet.
    await tester.tap(find.byKey(const ValueKey('levelRestore_x')));
    await tester.pumpAndSettle();
    expect(log, [SecurityLevel.d, null]);
    expect(find.text('Details · Stufe C · Standard'), findsOneWidget);
    expect(find.byKey(const ValueKey('levelRestore_x')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('levelDetails_x')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('level_x_a')), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('Hinweis bei lockernden Stufen: Abbrechen ändert nichts', (
    tester,
  ) async {
    final log = <SecurityLevel?>[];
    await tester.pumpWidget(
      TestEnv().app(
        home: _Host(
          start: SecurityLevel.d,
          base: SecurityLevel.d,
          warn: const {SecurityLevel.a, SecurityLevel.b},
          log: log,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('levelDetails_x')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('level_x_a')));
    await tester.pumpAndSettle();
    expect(find.text('Weniger Schutz?'), findsOneWidget);
    expect(find.text('Hinweis-Text'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(log, isEmpty);

    await tester.tap(find.byKey(const ValueKey('level_x_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trotzdem ändern'));
    await tester.pumpAndSettle();
    expect(log, [SecurityLevel.b]);

    // C steht nicht in warnLevels: ohne Hinweis.
    await tester.tap(find.byKey(const ValueKey('level_x_c')));
    await tester.pumpAndSettle();
    expect(find.text('Weniger Schutz?'), findsNothing);
    expect(log, [SecurityLevel.b, SecurityLevel.c]);
  });

  testWidgets('Golden Stufenwahl', tags: ['golden'], (tester) async {
    final env = TestEnv();
    await pumpGoldenScreen(
      tester,
      env,
      _Host(log: <SecurityLevel?>[], start: SecurityLevel.b),
    );
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/stufenwahl_eingeklappt.png'),
    );
    await tester.tap(find.byKey(const ValueKey('levelDetails_x')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('level_x_d')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/stufenwahl_ausgeklappt.png'),
    );
  });
}
