import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// Clock that follows the fake time of [async].
final class _FakeClock implements Clock {
  _FakeClock(this.async);

  final FakeAsync async;
  final _start = DateTime.utc(2026, 10, 14, 10);

  @override
  DateTime now() => _start.add(async.elapsed);
}

void main() {
  late int runs;
  UndoAction action([String label = 'Termin entfernen']) =>
      UndoAction(label: label, run: () async => runs++);

  setUp(() => runs = 0);

  test('undo innerhalb von 10 s läuft genau einmal', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async))..register('c1', action());
      async.elapse(const Duration(milliseconds: 9999));
      expect(m.canUndo('c1'), isTrue);
      bool? result;
      m.undo('c1').then((r) => result = r);
      async.flushMicrotasks();
      expect(result, isTrue);
      expect(runs, 1);
      m.undo('c1').then((r) => result = r);
      async.flushMicrotasks();
      expect(result, isFalse);
      expect(runs, 1);
    });
  });

  test('nach 10 s verfallen', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async))..register('c1', action());
      async.elapse(const Duration(seconds: 10));
      expect(m.canUndo('c1'), isFalse);
      expect(m.remaining('c1'), isNull);
      bool? result;
      m.undo('c1').then((r) => result = r);
      async.flushMicrotasks();
      expect(result, isFalse);
      expect(runs, 0);
    });
  });

  test('Countdown-Stream: Sekunden, dann expired', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async));
      final updates = <UndoUpdate>[];
      m.updates.listen(updates.add);
      m.register('c1', action());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 10));
      final pending = updates.where((u) => u.state == UndoState.pending);
      expect([for (final u in pending) u.remaining.inSeconds].take(3), [
        10,
        9,
        8,
      ]);
      expect(
        updates.last,
        const UndoUpdate(
          callId: 'c1',
          label: 'Termin entfernen',
          state: UndoState.expired,
          remaining: Duration.zero,
        ),
      );
      expect(updates.where((u) => u.state == UndoState.expired), hasLength(1));
      // No further ticks after expiry.
      final count = updates.length;
      async.elapse(const Duration(seconds: 5));
      expect(updates, hasLength(count));
    });
  });

  test('undo meldet undone und stoppt den Countdown', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async));
      final updates = <UndoUpdate>[];
      m.updates.listen(updates.add);
      m.register('c1', action());
      async.elapse(const Duration(seconds: 2));
      m.undo('c1');
      async.flushMicrotasks();
      expect(updates.last.state, UndoState.undone);
      expect(updates.last.remaining, Duration.zero);
      final count = updates.length;
      async.elapse(const Duration(seconds: 20));
      expect(updates, hasLength(count));
    });
  });

  test('remaining zählt herunter', () {
    fakeAsync((async) {
      final m = UndoManager(
        clock: _FakeClock(async),
        window: const Duration(seconds: 5),
      )..register('c1', action());
      async.elapse(const Duration(seconds: 2));
      expect(m.remaining('c1'), const Duration(seconds: 3));
      expect(m.remaining('unbekannt'), isNull);
    });
  });

  test('erneutes register ersetzt und startet neu', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async));
      final updates = <UndoUpdate>[];
      m.updates.listen(updates.add);
      m.register('c1', action('alt'));
      async.elapse(const Duration(seconds: 8));
      m.register('c1', action('neu'));
      async.elapse(const Duration(seconds: 8));
      expect(m.canUndo('c1'), isTrue);
      expect(updates.where((u) => u.state == UndoState.expired), isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(m.canUndo('c1'), isFalse);
      expect(updates.last.label, 'neu');
    });
  });

  test('Fehler der Aktion: failed statt undone, rethrow, Angebot ist weg', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async))
        ..register(
          'c1',
          UndoAction(label: 'x', run: () async => throw StateError('nein')),
        );
      final updates = <UndoUpdate>[];
      m.updates.listen(updates.add);
      Object? error;
      m.undo('c1').catchError((Object e) {
        error = e;
        return false;
      });
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(m.canUndo('c1'), isFalse);
      expect(updates.last.state, UndoState.failed);
      expect(updates.where((u) => u.state == UndoState.undone), isEmpty);
    });
  });

  test('undone erst nach Abschluss der Aktion', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final m = UndoManager(clock: _FakeClock(async))
        ..register('c1', UndoAction(label: 'x', run: () => gate.future));
      final updates = <UndoUpdate>[];
      m.updates.listen(updates.add);
      m.undo('c1');
      async.flushMicrotasks();
      expect(updates.where((u) => u.state == UndoState.undone), isEmpty);
      expect(m.canUndo('c1'), isFalse, reason: 'kein doppeltes Undo');
      gate.complete();
      async.flushMicrotasks();
      expect(updates.last.state, UndoState.undone);
    });
  });

  test('dispose stoppt Timer und schließt den Stream', () {
    fakeAsync((async) {
      final m = UndoManager(clock: _FakeClock(async))..register('c1', action());
      var done = false;
      m.updates.listen(null, onDone: () => done = true);
      m.dispose();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(async.pendingTimers, isEmpty);
      expect(m.canUndo('c1'), isFalse);
    });
  });

  test('UndoUpdate Gleichheit und toString', () {
    const a = UndoUpdate(
      callId: 'c',
      label: 'l',
      state: UndoState.pending,
      remaining: Duration(seconds: 1),
    );
    const b = UndoUpdate(
      callId: 'c',
      label: 'l',
      state: UndoState.pending,
      remaining: Duration(seconds: 1),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), 'UndoUpdate(c, pending, 1000 ms)');
  });
}
