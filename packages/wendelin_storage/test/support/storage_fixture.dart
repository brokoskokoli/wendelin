import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Fixed start time used across tests (local time).
final t0 = DateTime(2026, 10, 13, 9);

/// A fresh in-memory storage with a [FixedClock] at [t0] and sequential ids.
({WendelinStorage storage, FixedClock clock}) openTestStorage() {
  final clock = FixedClock(t0);
  final storage = openInMemoryStorage(
    clock: clock,
    ids: SequentialIdGenerator(),
  );
  return (storage: storage, clock: clock);
}
