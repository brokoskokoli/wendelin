// Selbsttests des Gate-Semaphors (WP97).
import 'dart:io';

import 'gate_lock.dart';
import 'self_check.dart';

Never _fail(String m) => throw StateError(m);

typedef _Mk = GateSlots Function(
  int own, {
  Future<void> Function(Duration)? sleep,
});

/// Prüfungen des Semaphors.
Future<void> gateLockChecks(SelfCheck t) async {
  slotsSync(t);
  await _slots(t);
}

void slotsSync(SelfCheck t) {
  t.group('Gate-Semaphor: Umgebung');
  t.eq(gateSlotsFromEnvironment({'HOME': '/h', 'CI': 'true'}), null, 'CI: aus');
  t.eq(
    gateSlotsFromEnvironment({'HOME': '/h', 'WENDELIN_GATE_SLOTS': '0'}),
    null,
    'WENDELIN_GATE_SLOTS=0: aus',
  );
  t.eq(gateSlotsFromEnvironment({'HOME': '/h'})?.max, 2, 'Standard: 2 Läufe');
}

Future<void> _slots(SelfCheck t) async {
  t.group('Gate-Semaphor');
  final tmp = Directory.systemTemp.createTempSync('gate_slots_');
  try {
    final alive = <int>{111, 222, 333};
    final msgs = <String>[];
    GateSlots slots(int own, {Future<void> Function(Duration)? sleep}) =>
        GateSlots(
          dir: Directory('${tmp.path}/s'),
          ownPid: own,
          isAlive: alive.contains,
          sleep: sleep ?? (_) async => _fail('unerwartetes Warten'),
          log: msgs.add,
          staleEmpty: Duration.zero,
        );

    final a = await slots(111).acquire();
    final b = await slots(222).acquire();
    t.isTrue(
      a.file != null && b.file != null && a.file!.path != b.file!.path,
      'zwei Läufe belegen zwei Slots',
    );
    t.isTrue(msgs.isEmpty, 'keine Meldung ohne Warten');

    var waits = 0;
    final third = await slots(
      333,
      sleep: (_) async {
        waits++;
        if (waits == 2) a.release();
      },
    ).acquire();
    t.eq(waits, 2, 'dritter Lauf wartet, bis ein Slot frei wird');
    t.isTrue(
      msgs.length == 1 && msgs.single.contains('Gate wartet'),
      'Wartemeldung genau einmal',
    );
    t.isTrue(
      third.file!.readAsStringSync() == '333',
      'Slot trägt die PID des Laufs',
    );

    alive.remove(222);
    msgs.clear();
    final fourth = await slots(444).acquire();
    t.eq(
      fourth.file!.path,
      b.file!.path,
      'Slot eines toten Prozesses wird übernommen',
    );
    t.eq(fourth.file!.readAsStringSync(), '444', 'neue PID im Slot');
    t.isTrue(msgs.isEmpty, 'tote PID: kein Warten');

    third.release();
    fourth.release();
    t.isTrue(
      Directory('${tmp.path}/s').listSync().isEmpty,
      'release räumt die Slot-Dateien auf',
    );
    fourth.release();
    await _reap(t, tmp, alive, msgs, slots);
    await _race(t, tmp, alive, msgs, slots);
    await _exceptions(t, tmp, slots, msgs);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

Future<void> _reap(
  SelfCheck t,
  Directory tmp,
  Set<int> alive,
  List<String> msgs,
  _Mk slots,
) async {
  // Leere Slot-Datei (Absturz zwischen Anlegen und Schreiben) ist verwaist.
  Directory('${tmp.path}/s/').createSync(recursive: true);
  File('${tmp.path}/s/slot-0.lock').createSync();
  File('${tmp.path}/s/slot-1.lock').writeAsStringSync('111');
  final e = await slots(555).acquire();
  t.eq(
    e.file!.path,
    '${tmp.path}/s/slot-0.lock',
    'leere Datei wird aufgeräumt',
  );
  e.release();
  File('${tmp.path}/s/slot-1.lock').deleteSync();

  // release löscht nur den eigenen Slot (Datei trägt noch die eigene PID).
  final own = await slots(111).acquire();
  own.file!.writeAsStringSync('222');
  own.release();
  t.isTrue(own.file!.existsSync(), 'release: fremde PID bleibt unberührt');
  own.file!.deleteSync();

  // Verwaister Aufräum-Wächter (älter als guardStale) wird verworfen.
  File('${tmp.path}/s/slot-0.lock').writeAsStringSync('999');
  File('${tmp.path}/s/slot-1.lock').writeAsStringSync('111');
  final guard = File('${tmp.path}/s/slot-0.lock.reap')..createSync();
  guard.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
  final stale = GateSlots(
    dir: Directory('${tmp.path}/s'),
    ownPid: 666,
    isAlive: alive.contains,
    sleep: (_) async => throw StateError('wartet'),
    log: msgs.add,
  );
  try {
    await stale.acquire();
  } on StateError {
    // erster Durchlauf: Wächter verworfen, Slot noch belegt
  }
  t.isTrue(!guard.existsSync(), 'alter Wächter wird verworfen');
  final after = await stale.acquire();
  t.eq(
    after.file!.path,
    '${tmp.path}/s/slot-0.lock',
    'toter Slot nach verworfenem Wächter aufgeräumt',
  );
  after.release();
  File('${tmp.path}/s/slot-1.lock').deleteSync();
}

Future<void> _race(
  SelfCheck t,
  Directory tmp,
  Set<int> alive,
  List<String> msgs,
  _Mk slots,
) async {
  // Rennen: zwischen Lesen und Löschen übernimmt ein anderer Lauf den Slot.
  File('${tmp.path}/s/slot-0.lock').writeAsStringSync('999');
  File('${tmp.path}/s/slot-1.lock').writeAsStringSync('111');
  var swapped = false;
  final racer = GateSlots(
    dir: Directory('${tmp.path}/s'),
    ownPid: 777,
    isAlive: (p) {
      if (p == 999 && !swapped) {
        swapped = true;
        File('${tmp.path}/s/slot-0.lock').writeAsStringSync('222');
      }
      return alive.contains(p);
    },
    sleep: (_) async => throw StateError('wartet'),
    log: msgs.add,
  );
  try {
    await racer.acquire();
    t.isTrue(false, 'alle Slots belegt: acquire muss warten');
  } on StateError {
    t.eq(
      File('${tmp.path}/s/slot-0.lock').readAsStringSync(),
      '222',
      'übernommener Slot wird nicht gelöscht',
    );
  }
  t.isTrue(
    !File('${tmp.path}/s/slot-0.lock.reap').existsSync(),
    'Aufräum-Wächter wird entfernt',
  );
  File('${tmp.path}/s/slot-0.lock').deleteSync();
  File('${tmp.path}/s/slot-1.lock').deleteSync();
}

Future<void> _exceptions(
  SelfCheck t,
  Directory tmp,
  _Mk slots,
  List<String> msgs,
) async {
  // withGateSlot gibt auch bei einer Ausnahme frei.
  try {
    await withGateSlot(slots(888), () async => throw StateError('boom'));
  } on StateError {
    // erwartet
  }
  t.isTrue(
    Directory('${tmp.path}/s').listSync().isEmpty,
    'Slot nach Ausnahme freigegeben',
  );
  var inside = false;
  await withGateSlot(slots(888), () async {
    inside = Directory('${tmp.path}/s').listSync().length == 1;
  });
  t.isTrue(inside, 'Slot während des Laufs belegt');
  t.isTrue(
    Directory('${tmp.path}/s').listSync().isEmpty,
    'Slot nach dem Lauf freigegeben',
  );
  await withGateSlot(null, () async {});

  // Ordner nicht anlegbar: fail-open.
  File('${tmp.path}/datei').writeAsStringSync('x');
  final open = await GateSlots(
    dir: Directory('${tmp.path}/datei/s'),
    log: msgs.add,
  ).acquire();
  t.isTrue(open.file == null, 'unbenutzbarer Ordner: Lauf ohne Sperre');
  open.release();
}
