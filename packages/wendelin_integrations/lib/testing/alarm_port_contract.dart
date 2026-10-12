import 'dart:async';

import 'package:test/test.dart';

import '../src/alarms/alarms.dart';
import '../src/common/port_exception.dart';

/// Creates the [AlarmPort] under test.
typedef AlarmPortFactory = FutureOr<AlarmPort> Function();

/// Label of alarms and timers created by [alarmPortContract].
const alarmContractLabel = 'Wendelin-Contract';

/// Names of the checks in [alarmPortContractChecks].
abstract final class AlarmPortChecks {
  /// Out-of-range values throw ArgumentError.
  static const invalid = 'ungültige Werte werfen ArgumentError';

  /// A returned id is listed, cancel removes it, cancelling again is
  /// notFound.
  static const alarmLifecycle =
      'setAlarm: Id erscheint in listAlarms, cancel entfernt, '
      'zweites cancel ist notFound';

  /// Repeat days are stored.
  static const days = 'Wiederholungstage werden übernommen';

  /// A timer can be started and, with an id, cancelled.
  static const timer = 'setTimer läuft, Id (falls vorhanden) ist abbrechbar';

  /// Cancelling an unknown id is notFound.
  static const unknownCancel = 'cancel mit unbekannter Id ist notFound';
}

/// Reusable contract suite for every [AlarmPort] implementation; registers
/// one test per entry of [alarmPortContractChecks].
///
/// On a real device this sets alarms at 03:17/03:18 and a 1-hour timer
/// labelled [alarmContractLabel]; they are cancelled again when the
/// platform returns ids. Platforms without ids (Android intents) can only
/// be checked partially.
void alarmPortContract(AlarmPortFactory create, {String name = 'AlarmPort'}) {
  group('$name erfüllt den AlarmPort-Vertrag', () {
    alarmPortContractChecks(create).forEach(test);
  });
}

/// The checks of [alarmPortContract] by name ([AlarmPortChecks]).
Map<String, Future<void> Function()> alarmPortContractChecks(
  AlarmPortFactory create,
) {
  final notFound = throwsA(
    isA<PortException>().having((e) => e.kind, 'kind', PortErrorKind.notFound),
  );

  Future<void> withPort(
    Future<void> Function(AlarmPort p, List<String> ids) body,
  ) async {
    final port = await create();
    final ids = <String>[];
    try {
      await body(port, ids);
    } finally {
      for (final id in ids) {
        try {
          await port.cancel(id);
        } on PortException {
          // Bereits gelöscht.
        }
      }
    }
  }

  return {
    AlarmPortChecks.invalid: () => withPort((p, _) async {
      final invalid = throwsA(isA<ArgumentError>());
      await expectLater(p.setAlarm(hour: 24, minute: 0), invalid);
      await expectLater(p.setAlarm(hour: -1, minute: 0), invalid);
      await expectLater(p.setAlarm(hour: 7, minute: 60), invalid);
      await expectLater(p.setAlarm(hour: 7, minute: 0, days: {0}), invalid);
      await expectLater(p.setAlarm(hour: 7, minute: 0, days: {8}), invalid);
      await expectLater(p.setTimer(duration: Duration.zero), invalid);
    }),
    AlarmPortChecks.alarmLifecycle: () => withPort((p, ids) async {
      final id = await p.setAlarm(
        hour: 3,
        minute: 17,
        label: alarmContractLabel,
      );
      final listed = await p.listAlarms();
      if (id == null) {
        // Plattform ohne Handle (Android-Intent): nur die Liste ist prüfbar.
        if (listed != null) {
          expect(listed.any((a) => a.hour == 3 && a.minute == 17), isTrue);
        }
        return;
      }
      ids.add(id);
      if (listed != null) {
        final mine = listed.where((a) => a.id == id);
        expect(mine, hasLength(1), reason: 'gestellter Wecker gelistet');
        expect(mine.single.hour, 3);
        expect(mine.single.minute, 17);
        expect(mine.single.label, alarmContractLabel);
        expect(mine.single.days, isEmpty);
      }
      await p.cancel(id);
      ids.remove(id);
      final after = await p.listAlarms();
      if (after != null) {
        expect(after.any((a) => a.id == id), isFalse, reason: 'gelöscht');
      }
      await expectLater(p.cancel(id), notFound);
    }),
    AlarmPortChecks.days: () => withPort((p, ids) async {
      final id = await p.setAlarm(
        hour: 3,
        minute: 18,
        label: alarmContractLabel,
        days: {1, 3, 5},
      );
      if (id == null) return;
      ids.add(id);
      final listed = await p.listAlarms();
      if (listed == null) return;
      expect(listed.singleWhere((a) => a.id == id).days, {1, 3, 5});
    }),
    AlarmPortChecks.timer: () => withPort((p, ids) async {
      final id = await p.setTimer(
        duration: const Duration(hours: 1),
        label: alarmContractLabel,
      );
      if (id == null) return;
      await p.cancel(id);
      await expectLater(p.cancel(id), notFound);
    }),
    AlarmPortChecks.unknownCancel: () => withPort((p, _) async {
      await expectLater(p.cancel('wendelin-contract-unknown'), notFound);
    }),
  };
}
