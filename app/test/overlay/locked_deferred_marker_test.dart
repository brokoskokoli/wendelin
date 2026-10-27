// WP163 B: welche Werkzeuge nur entsperrt arbeiten (`WorksOnlyUnlocked`).
// Jede Änderung der Liste bricht diesen Test und braucht eine Prüfung: Das
// Werkzeug startet eine App oder ändert den Bildschirm, der gesperrt nichts
// erreichen würde, und wird bis zum Entsperren zurückgestellt.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integration_providers.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';

void main() {
  test('genau die markierten Werkzeuge tragen WorksOnlyUnlocked', () {
    final env = TestEnv(demo: true, realDemoPorts: true);
    final c = env.container();
    addTearDown(c.dispose);
    final tools = <Tool>[
      for (final i in c.read(integrationsProvider).values) ...i.tools,
    ];
    final names = {for (final t in tools) t.name};
    // Not vacuous: the integrations that hold the marked tools are built.
    expect(
      names,
      containsAll([
        'maps__navigate',
        'maps__search_place',
        'location__navigate_to',
        'media__open_audible',
        'obsidian__open_note',
        'phone__call',
        'flashlight__on',
      ]),
    );
    expect(
      {
        for (final t in tools)
          if (t is WorksOnlyUnlocked) t.name,
      },
      {
        'maps__navigate',
        'maps__search_place',
        'location__navigate_to',
        'media__open_audible',
        'obsidian__open_note',
        'phone__call',
      },
    );
  });
}
