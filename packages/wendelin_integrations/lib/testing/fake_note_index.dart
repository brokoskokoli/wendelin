import '../src/common/matching.dart';
import '../src/obsidian/ports.dart';
import 'fake_failures.dart';

/// In-memory [NoteIndexPort] with a simple ranking: notes matching more
/// query words first, then title matches before folder and body
/// matches. Words are
/// matched as prefixes, case and umlauts ignored.
final class FakeNoteIndex with FakeFailures implements NoteIndexPort {
  /// Indexed notes by path.
  final Map<String, ({String title, String body, DateTime modifiedAt})> notes =
      {};

  static List<String> _words(String s) =>
      normalizeText(s).split(' ').where((w) => w.isNotEmpty).toList();

  @override
  Future<void> upsert(
    String path, {
    required String title,
    required String body,
    required DateTime modifiedAt,
  }) async {
    enter('upsert');
    notes[path] = (title: title, body: body, modifiedAt: modifiedAt);
  }

  /// Number of [upsertAll] calls.
  int batches = 0;

  @override
  Future<void> upsertAll(List<IndexedNote> notes) async {
    enter('upsertAll');
    batches++;
    for (final n in notes) {
      this.notes[n.path] = (
        title: n.title,
        body: n.body,
        modifiedAt: n.modifiedAt,
      );
    }
  }

  @override
  Future<void> remove(String path) async {
    enter('remove');
    notes.remove(path);
  }

  @override
  Future<Map<String, DateTime>> knownFiles() async {
    enter('knownFiles');
    return {for (final e in notes.entries) e.key: e.value.modifiedAt};
  }

  @override
  Future<List<NoteHit>> search(String query, {int limit = 10}) async {
    enter('search');
    final terms = _words(query).where((w) => w.length >= 2).toSet();
    if (terms.isEmpty || limit <= 0) return const [];
    final scored = <(int, String)>[];
    for (final MapEntry(key: path, value: n) in notes.entries) {
      final title = _words(n.title);
      final body = _words(n.body);
      final folders = _words(path.split('/').reversed.skip(1).join(' '));
      var distinct = 0;
      var score = 0;
      for (final t in terms) {
        final inTitle = title.where((w) => w.startsWith(t)).length;
        final inBody = body.where((w) => w.startsWith(t)).length;
        final inPath = folders.where((w) => w.startsWith(t)).length;
        if (inTitle + inBody + inPath > 0) distinct++;
        score += inTitle * 10 + inPath * 2 + inBody;
      }
      if (distinct > 0) scored.add((distinct * 1000 + score, path));
    }
    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    return [
      for (final (_, path) in scored.take(limit))
        NoteHit(
          path: path,
          title: notes[path]!.title,
          snippet: _snippet(notes[path]!.body, terms),
        ),
    ];
  }

  static String _snippet(String body, Set<String> terms) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = normalizeText(flat);
    var at = -1;
    for (final t in terms) {
      final i = lower.indexOf(t);
      if (i >= 0 && (at < 0 || i < at)) at = i;
    }
    // normalizeText kann Positionen verschieben (ß → ss); grob genügt.
    final start = at < 0 ? 0 : (at - 40).clamp(0, flat.length);
    final end = (start + 120).clamp(0, flat.length);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}'
        '${end < flat.length ? '…' : ''}';
  }
}
