import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/session_lock_store.dart';
import 'package:wendelin/di/session_manager.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart'
    show SessionOrigin, WendelinStorage;

final class _Stamp implements AbsenceStamp {
  DateTime? value;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<DateTime?> load() async {
    if (failLoad) throw const FormatException('kaputt');
    return value;
  }

  @override
  Future<void> save(DateTime? at) async {
    if (failSave) throw StateError('voll');
    value = at;
  }
}

void main() {
  late FixedClock clock;
  late WendelinStorage storage;
  late _Stamp stamp;
  late List<String> ended;

  SessionManager make({
    AbsenceStamp? absence,
    SessionOrigin origin = SessionOrigin.app,
  }) => SessionManager(
    conversations: storage.conversations,
    clock: clock,
    onSessionEnd: ended.add,
    origin: origin,
    absence: absence ?? stamp,
  );

  setUp(() {
    clock = FixedClock(DateTime(2026, 10, 26, 8));
    storage = openInMemoryStorage(clock: clock);
    stamp = _Stamp();
    ended = [];
  });

  test('unter 1 min weg: gleiche Sitzung, kein Ende', () async {
    final m = make();
    addTearDown(m.dispose);
    final a = await m.ensure();
    await storage.conversations.append(a, Message.user('x'));
    m.leftScreen();
    clock.advance(const Duration(seconds: 59));
    expect(await m.returnedToScreen(), isFalse);
    expect(await m.ensure(), a);
    expect(ended, isEmpty);
    expect(stamp.value, isNull, reason: 'Zeitpunkt wieder gelöscht');
  });

  test('ab 1 min weg: Sitzung endet, nächste Anfrage neu', () async {
    final m = make();
    addTearDown(m.dispose);
    final a = await m.ensure();
    await storage.conversations.append(a, Message.user('x'));
    m.leftScreen();
    clock.advance(const Duration(minutes: 1));
    expect(await m.returnedToScreen(), isTrue);
    expect(ended, [a]);
    final b = await m.ensure();
    expect(b, isNot(a), reason: 'trotz 5-min-Fenster der Datenbank');
  });

  test('Timer beendet die Sitzung im Hintergrund nach 1 min', () {
    fakeAsync((async) {
      final m = make();
      String? id;
      m.ensure().then((v) => id = v);
      async.flushMicrotasks();
      m.leftScreen();
      async.elapse(const Duration(seconds: 59));
      expect(ended, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(ended, [id]);
      m.dispose();
    });
  });

  test('zweites hidden/paused behält den ersten Zeitpunkt', () async {
    final m = make();
    addTearDown(m.dispose);
    await m.ensure();
    m.leftScreen();
    clock.advance(const Duration(seconds: 40));
    m.leftScreen();
    clock.advance(const Duration(seconds: 40));
    expect(await m.returnedToScreen(), isTrue);
  });

  test('Neustart nach Kill: über 1 min neu, unter 1 min weiter', () async {
    final first = make();
    final a = await first.ensure();
    await storage.conversations.append(a, Message.user('x'));
    first.leftScreen();
    await Future<void>.delayed(Duration.zero);
    first.dispose(); // Prozess getötet
    expect(stamp.value, isNotNull);

    clock.advance(const Duration(seconds: 30));
    final soon = make();
    addTearDown(soon.dispose);
    expect(await soon.returnedToScreen(), isFalse);
    expect(await soon.ensure(), a);

    soon.leftScreen();
    await Future<void>.delayed(Duration.zero);
    soon.dispose();
    clock.advance(const Duration(minutes: 2));
    final late = make();
    addTearDown(late.dispose);
    expect(await late.returnedToScreen(), isTrue);
    expect(await late.ensure(), isNot(a));
  });

  test('unlesbarer Zeitpunkt: neue Sitzung (fail-closed)', () async {
    final m = make();
    addTearDown(m.dispose);
    final a = await m.ensure();
    await storage.conversations.append(a, Message.user('x'));
    final restarted = make();
    addTearDown(restarted.dispose);
    stamp.failLoad = true;
    expect(await restarted.returnedToScreen(), isTrue);
    expect(await restarted.ensure(), isNot(a));
  });

  test('Zeitpunkt in der Zukunft (Uhr zurückgestellt): neue Sitzung', () async {
    stamp.value = clock.now().add(const Duration(hours: 1));
    final m = make();
    addTearDown(m.dispose);
    expect(await m.returnedToScreen(), isTrue);
  });

  test('Zeitpunkt nicht speicherbar: Sitzung endet sofort', () async {
    final m = make();
    addTearDown(m.dispose);
    final a = await m.ensure();
    stamp.failSave = true;
    m.leftScreen();
    await Future<void>.delayed(Duration.zero);
    expect(ended, [a]);
  });

  test('Overlay: ohne Stempel, nie betroffen', () async {
    final m = SessionManager(
      conversations: storage.conversations,
      clock: clock,
      onSessionEnd: ended.add,
      origin: SessionOrigin.overlay,
    );
    addTearDown(m.dispose);
    expect(await m.returnedToScreen(), isFalse);
  });

  test('SettingsAbsenceStamp: Roundtrip, löschen, beschädigt', () async {
    final s = SettingsAbsenceStamp(storage.settings);
    expect(await s.load(), isNull);
    final t = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    await s.save(t);
    expect(await s.load(), t);
    await s.save(null);
    expect(await s.load(), isNull);
  });
}
