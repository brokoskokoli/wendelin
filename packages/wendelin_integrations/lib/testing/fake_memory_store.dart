import 'package:wendelin_core/wendelin_core.dart';

import '../src/common/port_exception.dart';
import '../src/memory/memory.dart';
import 'fake_failures.dart';

/// In-memory [MemoryStorePort] with simple word-overlap search; rejects
/// sensitive content via core's [detectSensitiveContent].
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
  final Map<String, String> _owners = {};

  /// Stored entries of all namespaces, oldest first.
  List<MemoryEntry> get entries => List.unmodifiable(_entries);

  /// Entries of the namespace [owner], oldest first.
  List<MemoryEntry> entriesOf(String owner) => [
    for (final e in _entries)
      if (_owners[e.id] == owner) e,
  ];

  /// Entries that belong to [owner].
  bool _mine(MemoryEntry e, String owner) => _owners[e.id] == owner;

  @override
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
    PrivacyLevel? privacyFloor,
    String owner = '',
  }) async {
    enter('save');
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'darf nicht leer sein');
    }
    final finding = detectSensitiveContent(text);
    if (finding != null) {
      throw PortException(PortErrorKind.rejected, finding.reason);
    }
    final entry = MemoryEntry(
      id: ids.next(),
      text: text.trim(),
      category: category,
      source: source,
      createdAt: clock.now(),
      privacyFloor: privacyFloor,
    );
    _entries.add(entry);
    _owners[entry.id] = owner;
    return entry;
  }

  @override
  Future<List<MemoryEntry>> search(
    String query, {
    int limit = 5,
    String owner = '',
  }) async {
    enter('search');
    final words = _words(query);
    final scored = <(int, int, MemoryEntry)>[];
    for (var i = 0; i < _entries.length; i++) {
      if (!_mine(_entries[i], owner)) continue;
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
          privacyFloor: e.privacyFloor,
        ),
    ];
  }

  @override
  Future<MemoryEntry> forget(String id, {String owner = ''}) async {
    enter('forget');
    final i = _entries.indexWhere((e) => e.id == id && _mine(e, owner));
    if (i < 0) {
      throw PortException(
        PortErrorKind.notFound,
        'Erinnerung „$id“ gibt es nicht',
      );
    }
    _owners.remove(id);
    return _entries.removeAt(i);
  }

  @override
  Future<List<MemoryEntry>> list({String owner = ''}) async {
    enter('list');
    return [
      for (final e in _entries.reversed)
        if (_mine(e, owner)) e,
    ];
  }

  static Set<String> _words(String text) => {
    for (final w in text.toLowerCase().split(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    ))
      if (w.length > 1) w,
  };
}
