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

  /// A timer can be started and cancelled.
  static const timer = 'setTimer liefert Id und ist abbrechbar';

  /// Cancelling an unknown id is notFound (unsupported without cancel).
  static const unknownCancel =
      'cancel mit unbekannter Id: notFound bzw. unsupported';
}

/// Reusable contract suite for every [AlarmPort] implementation; registers
/// one test per entry of [alarmPortContractChecks].
///
/// The suite never leaves alarms behind: alarms and timers are only created
/// when the port reports [AlarmPort.supportsCancel], and they are cancelled
/// again. For ports without cancel (Android intents) only argument
/// validation and `cancel` errors are checked; nothing is set on the device.
void alarmPortContract(AlarmPortFactory create, {String name = 'AlarmPort'}) {
  group('$name erfüllt den AlarmPort-Vertrag', () {
    alarmPortContractChecks(create).forEach(test);
  });
}

/// The checks of [alarmPortContract] by name ([AlarmPortChecks]).
Map<String, Future<void> Function()> alarmPortContractChecks(
  AlarmPortFactory create,
) {
  Matcher port(PortErrorKind kind) =>
      throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind));

  /// Runs [body] only for ports that can cancel; cancels every id in
  /// `ids` afterwards.
  Future<void> withCancellable(
    Future<void> Function(AlarmPort p, List<String> ids) body,
  ) async {
    final p = await create();
    if (!p.supportsCancel) return;
    final ids = <String>[];
    try {
      await body(p, ids);
    } finally {
      for (final id in ids) {
        try {
          await p.cancel(id);
        } on PortException {
          // Bereits gelöscht.
        }
      }
    }
  }

  Future<String> requireId(Future<String?> f, List<String> ids) async {
    final id = await f;
    expect(id, isNotNull, reason: 'supportsCancel verlangt eine Id');
    ids.add(id!);
    return id;
  }

  return {
    AlarmPortChecks.invalid: () async {
      final p = await create();
      final invalid = throwsA(isA<ArgumentError>());
      await expectLater(p.setAlarm(hour: 24, minute: 0), invalid);
      await expectLater(p.setAlarm(hour: -1, minute: 0), invalid);
      await expectLater(p.setAlarm(hour: 7, minute: 60), invalid);
      await expectLater(p.setAlarm(hour: 7, minute: 0, days: {0}), invalid);
      await expectLater(p.setAlarm(hour: 7, minute: 0, days: {8}), invalid);
      await expectLater(p.setTimer(duration: Duration.zero), invalid);
    },
    AlarmPortChecks.alarmLifecycle: () => withCancellable((p, ids) async {
      final id = await requireId(
        p.setAlarm(hour: 3, minute: 17, label: alarmContractLabel),
        ids,
      );
      final listed = await p.listAlarms();
      if (listed != null && !p.listsOnlyNext) {
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
      await expectLater(p.cancel(id), port(PortErrorKind.notFound));
    }),
    AlarmPortChecks.days: () => withCancellable((p, ids) async {
      final id = await requireId(
        p.setAlarm(
          hour: 3,
          minute: 18,
          label: alarmContractLabel,
          days: {1, 3, 5},
        ),
        ids,
      );
      final listed = await p.listAlarms();
      if (listed == null || p.listsOnlyNext) return;
      expect(listed.singleWhere((a) => a.id == id).days, {1, 3, 5});
    }),
    AlarmPortChecks.timer: () => withCancellable((p, ids) async {
      final id = await requireId(
        p.setTimer(
          duration: const Duration(hours: 1),
          label: alarmContractLabel,
        ),
        ids,
      );
      await p.cancel(id);
      ids.remove(id);
      await expectLater(p.cancel(id), port(PortErrorKind.notFound));
    }),
    AlarmPortChecks.unknownCancel: () async {
      final p = await create();
      await expectLater(
        p.cancel('wendelin-contract-unknown'),
        port(
          p.supportsCancel ? PortErrorKind.notFound : PortErrorKind.unsupported,
        ),
      );
    },
  };
}
