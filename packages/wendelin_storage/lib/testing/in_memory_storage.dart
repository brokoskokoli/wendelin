import 'package:drift/native.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../src/storage.dart';

/// Opens a [WendelinStorage] on a fresh in-memory SQLite database (tests,
/// evals, demo mode). Nothing is persisted.
WendelinStorage openInMemoryStorage({
  Clock clock = const SystemClock(),
  IdGenerator? ids,
}) => WendelinStorage(NativeDatabase.memory(), clock: clock, ids: ids);
