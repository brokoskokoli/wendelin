import 'package:wendelin_core/wendelin_core.dart';

import '../src/common/port_exception.dart';
import '../src/memory/memory.dart';
import '../src/memory/sensitive_content.dart';
import 'fake_failures.dart';

/// In-memory [MemoryStorePort] with simple word-overlap search and the same
/// sensitivity rule as the real store.
final class FakeMemoryStore with FakeFailures implements MemoryStorePort {
  /// Creates the fake; [clock] and [ids] default to a fixed clock and
  /// sequential ids `m1`, `m2`, ….
  FakeMemoryStore({Clock? clock, IdGenerator? ids})
    : clock = clock ?? FixedClock(DateTime.utc(2026, 10, 13, 12)),
      ids = ids ?? SequentialIdGenerator(prefix: 'm');

  /// Time source for `createdAt`/`lastUsedAt`.
  final Clock clock;

  /// Id source.
  final IdGenerator ids;

  final List<MemoryEntry> _entries = [];

  /// Stored entries, oldest first.
  List<MemoryEntry> get entries => List.unmodifiable(_entries);

  @override
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
  }) async {
    enter('save');
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'darf nicht leer sein');
    }
    final reason = sensitiveContentReason(text);
    if (reason != null) throw PortException(PortErrorKind.rejected, reason);
    final entry = MemoryEntry(
      id: ids.next(),
      text: text.trim(),
      category: category,
      source: source,
      createdAt: clock.now(),
    );
    _entries.add(entry);
    return entry;
  }

  @override
  Future<List<MemoryEntry>> search(String query, {int limit = 5}) async {
    enter('search');
    final words = _words(query);
    final scored = <(int, int, MemoryEntry)>[];
    for (var i = 0; i < _entries.length; i++) {
      final score = _words(_entries[i].text).intersection(words).length;
      if (score > 0) scored.add((score, i, _entries[i]));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : b.$2 - a.$2);
    final now = clock.now();
    return [
      for (final (_, i, e) in scored.take(limit))
        _entries[i] = MemoryEntry(
          id: e.id,
          text: e.text,
          category: e.category,
          source: e.source,
          createdAt: e.createdAt,
          lastUsedAt: now,
        ),
    ];
  }

  @override
  Future<MemoryEntry> forget(String id) async {
    enter('forget');
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0) {
      throw PortException(
        PortErrorKind.notFound,
        'Erinnerung „$id“ gibt es nicht',
      );
    }
    return _entries.removeAt(i);
  }

  @override
  Future<List<MemoryEntry>> list() async {
    enter('list');
    return _entries.reversed.toList();
  }

  static Set<String> _words(String text) => {
    for (final w in text.toLowerCase().split(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    ))
      if (w.length > 1) w,
  };
}
