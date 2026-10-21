// WP114 (K85): Freigabeliste für das gesperrte Gerät. Jede Erweiterung
// bricht diesen Test und braucht eine Sicherheitsprüfung (Begründung je
// Werkzeug in `lockedToolName`, docs/testing/m5/wp114.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integrations/registry.dart';
import 'package:wendelin/voice/locked_agent_run.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('nur die Taschenlampe ist ohne Entsperren freigegeben', () {
    expect(
      {
        for (final s in builtInIntegrationSpecs)
          if (s.allowedWhileLocked) s.id,
      },
      {'flashlight'},
    );
    expect(
      {for (final c in LockedCommand.values) lockedToolName(c)},
      {'flashlight__on', 'flashlight__off'},
    );
  });
}
