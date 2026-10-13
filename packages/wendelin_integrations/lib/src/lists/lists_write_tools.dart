import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import 'lists.dart';
import 'markdown_list.dart';

/// `lists__add_items` (write; undo removes exactly the added lines).
final class AddItemsTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool.
  const AddItemsTool(this.env);

  /// Shared state.
  final ListsEnv env;

  /// Most items per call.
  static const maxItems = 50;

  @override
  String get name => 'lists__add_items';

  @override
  String get description =>
      'Add one or more items to a list. Example: list "Einkaufen", items '
      '["Milch", "Eier"]. Items already open on the list are skipped.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'list': listProp,
      'items': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'One entry per item, without "- [ ]".',
      },
    },
    'required': ['list', 'items'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  List<String> _items(ToolArgs args) {
    final raw = args.optStringList('items');
    if (raw == null || raw.isEmpty) {
      throw const InvalidArgumentsException('„items“ fehlt');
    }
    if (raw.length > maxItems) {
      throw const InvalidArgumentsException(
        'Zu viele Einträge (höchstens $maxItems)',
      );
    }
    for (final i in raw) {
      if (i.isEmpty) throw const InvalidArgumentsException('Leerer Eintrag');
      if (i.contains('\n') || i.contains('\r')) {
        throw const InvalidArgumentsException('Einträge ohne Zeilenumbruch');
      }
    }
    return raw;
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final def = env.resolve(args.requireString('list'), write: true);
    final wanted = _items(args);
    return env.exclusive(def.target, () => _add(def, wanted));
  }

  Future<ToolOutcome> _add(ListDefinition def, List<String> wanted) async {
    final l = await env.load(def);
    final doc = l.doc;
    final present = {
      for (final i in l.items)
        if (!i.done) flat(i.text),
    };
    final added = <String>[];
    final skipped = <String>[];
    for (final text in wanted) {
      if (present.add(flat(text))) {
        added.add(text);
      } else {
        skipped.add(text);
      }
    }
    if (added.isEmpty) {
      return jsonOutcome({
        'list': def.name,
        'added': <String>[],
        'already_present': skipped,
      }, summary: '${def.name}: schon vorhanden');
    }
    var range = l.range;
    String? heading;
    var addedBlank = false;
    if (range == null) {
      // Abschnitt fehlt: Überschrift am Dateiende anlegen.
      addedBlank =
          doc.lines.isNotEmpty && doc.lines.last.text.trim().isNotEmpty;
      heading = '## ${def.section!.replaceFirst(RegExp(r'^#+\s*'), '')}';
      doc.insert(doc.lines.length, [if (addedBlank) '', heading]);
      range = doc.scope(def.section)!;
    }
    final point = doc.insertionPoint(range);
    final lines = [for (final t in added) '${point.prefix}[ ] $t'];
    doc.insert(point.at, lines);
    await env.save(l);
    return jsonOutcome(
      {
        'list': def.name,
        'added': added,
        if (skipped.isNotEmpty) 'already_present': skipped,
      },
      summary: '${def.name}: ${added.join(', ')} hinzugefügt',
      undo: UndoAction(
        label: 'Einträge entfernen',
        run: () => env.exclusive(
          def.target,
          () => _undoAdd(def, lines, point.at, heading, addedBlank),
        ),
      ),
    );
  }

  Future<void> _undoAdd(
    ListDefinition def,
    List<String> lines,
    int near,
    String? heading,
    bool addedBlank,
  ) async {
    final l = await env.load(def);
    final doc = l.doc;
    final missing = <String>[];
    for (final text in lines) {
      final r = l.range;
      final i = r == null
          ? null
          : doc.findLine(text, near, from: r.start, to: r.end);
      if (i == null) {
        missing.add(text);
        continue;
      }
      doc.remove(i, i + 1);
    }
    if (missing.length == lines.length) {
      throw const PortException(
        PortErrorKind.notFound,
        'Rückgängig nicht möglich: Die Einträge wurden inzwischen geändert '
        'oder entfernt',
      );
    }
    if (heading != null) {
      final r = doc.scope(def.section);
      final empty =
          r != null &&
          doc.lines.sublist(r.start, r.end).every((x) => x.text.trim().isEmpty);
      if (r != null && empty && doc.lines[r.start - 1].text == heading) {
        final h = r.start - 1;
        final blank = addedBlank && h > 0 && doc.lines[h - 1].text.isEmpty;
        doc.remove(blank ? h - 1 : h, r.end);
      }
    }
    await env.save(l);
    if (missing.isNotEmpty) {
      throw PortException(
        PortErrorKind.notFound,
        'Nur teilweise rückgängig: ${missing.length} von ${lines.length} '
        'Einträgen wurden inzwischen geändert und bleiben stehen',
      );
    }
  }

  @override
  String describe(ToolArgs args) =>
      '${_items(args).join(', ')} zur Liste ${args.requireString('list')} '
      'hinzufügen';

  @override
  String get fallbackDescription => 'Zur Liste hinzufügen';
}

/// `lists__complete_item` (write; undo unchecks again).
final class CompleteItemTool extends IntegrationTool {
  /// Creates the tool.
  const CompleteItemTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'lists__complete_item';

  @override
  String get description =>
      'Check off an item on a list. Example: list "Einkaufen", item "Milch".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'list': listProp,
      'item': {
        'type': 'string',
        'description': 'The item, roughly as written.',
      },
    },
    'required': ['list', 'item'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final def = env.resolve(args.requireString('list'), write: true);
    final query = args.requireString('item');
    return env.exclusive(def.target, () async {
      final l = await env.load(def);
      // Abhaken ist rückgängig machbar: ein eindeutiger Treffer über ganze
      // Wörter („Milch“ → „Milch (1 l)“) wird ohne Rückfrage genommen.
      final item = pickItem(query, l.items, def.name, write: false);
      if (item.done) {
        return jsonOutcome({
          'list': def.name,
          'already_done': item.text,
        }, summary: '${item.text} war schon erledigt');
      }
      l.doc.setDone(item.line, true);
      final checked = l.doc.lines[item.line].text;
      await env.save(l);
      return jsonOutcome(
        {'list': def.name, 'completed': item.text},
        summary: '${def.name}: ${item.text} erledigt',
        undo: UndoAction(
          label: 'Wieder offen',
          run: () => env.exclusive(def.target, () async {
            final fresh = await env.load(def);
            final r = fresh.range;
            final i = r == null
                ? null
                : fresh.doc.findLine(
                    checked,
                    item.line,
                    from: r.start,
                    to: r.end,
                  );
            if (i == null) {
              throw const PortException(
                PortErrorKind.notFound,
                'Rückgängig nicht möglich: Der Eintrag wurde inzwischen '
                'geändert oder entfernt',
              );
            }
            fresh.doc.setDone(i, false);
            await env.save(fresh);
          }),
        ),
      );
    });
  }

  @override
  String describe(ToolArgs args) =>
      '${args.requireString('item')} auf ${args.requireString('list')} '
      'abhaken';

  @override
  String get fallbackDescription => 'Eintrag abhaken';
}

/// `lists__remove_item` (write; undo puts the lines back at the same
/// place).
final class RemoveItemTool extends IntegrationTool {
  /// Creates the tool.
  const RemoveItemTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'lists__remove_item';

  @override
  String get description =>
      'Delete an item from a list (open or done). Example: list "Einkaufen", '
      'item "Eier".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'list': listProp,
      'item': {
        'type': 'string',
        'description': 'The item, roughly as written.',
      },
    },
    'required': ['list', 'item'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final def = env.resolve(args.requireString('list'), write: true);
    final query = args.requireString('item');
    return env.exclusive(def.target, () async {
      final l = await env.load(def);
      final item = pickItem(query, l.items, def.name, write: true);
      return _remove(l, item);
    });
  }

  Future<ToolOutcome> _remove(LoadedList l, ListItem item) async {
    final def = l.definition;
    final doc = l.doc;
    // Anker: nächste nicht leere Zeile davor (mit Zahl der Leerzeilen
    // dazwischen) und danach; gesucht wird nur im Abschnitt.
    var p = item.line - 1;
    while (p >= 0 && doc.lines[p].text.trim().isEmpty) {
      p--;
    }
    final before = p >= 0 ? doc.lines[p].text : null;
    final gapBefore = item.line - p - 1;
    var n = item.end;
    while (n < doc.lines.length && doc.lines[n].text.trim().isEmpty) {
      n++;
    }
    final after = n < doc.lines.length ? doc.lines[n].text : null;
    final gapAfter = n - item.end;
    final terminator = item.line > 0 ? doc.lines[item.line - 1].eol : null;
    final removed = doc.remove(item.line, item.end);
    await env.save(l);
    return jsonOutcome(
      {'list': def.name, 'removed': item.text},
      summary: '${def.name}: ${item.text} entfernt',
      undo: UndoAction(
        label: 'Wiederherstellen',
        run: () => env.exclusive(def.target, () async {
          final fresh = await env.load(def);
          final d = fresh.doc;
          final r = fresh.range ?? (start: d.lines.length, end: d.lines.length);
          bool blank(int i) => d.lines[i].text.trim().isEmpty;
          int? at;
          final b = before == null
              ? null
              : d.findLine(before, p, from: r.start, to: r.end);
          if (b != null) {
            at = b + 1;
            for (var k = 0; k < gapBefore && at! < r.end && blank(at); k++) {
              at++;
            }
          } else if (after != null) {
            final a = d.findLine(after, item.line, from: r.start, to: r.end);
            if (a != null) {
              at = a;
              for (
                var k = 0;
                k < gapAfter && at! > r.start && blank(at - 1);
                k++
              ) {
                at--;
              }
            }
          }
          at ??= before == null ? r.start : item.line.clamp(r.start, r.end);
          final atEnd = at >= d.lines.length;
          d.insert(
            at,
            [for (final x in removed) x.text],
            eols: [
              for (final x in removed)
                x.eol.isEmpty && !atEnd ? d.defaultEol : x.eol,
            ],
            terminator: terminator == null || terminator.isEmpty
                ? null
                : terminator,
          );
          await env.save(fresh);
        }),
      ),
    );
  }

  @override
  String describe(ToolArgs args) =>
      '${args.requireString('item')} von ${args.requireString('list')} '
      'entfernen';

  @override
  String get fallbackDescription => 'Eintrag entfernen';
}

/// `lists__clear_completed` (external: always confirmed).
final class ClearCompletedTool extends IntegrationTool {
  /// Creates the tool.
  const ClearCompletedTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'lists__clear_completed';

  @override
  String get description =>
      'Delete all checked items from a list. The user is asked to confirm.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {'list': listProp},
    'required': ['list'],
  };

  @override
  RiskLevel get risk => RiskLevel.external;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final def = env.resolve(args.requireString('list'), write: true);
    return env.exclusive(def.target, () async {
      final l = await env.load(def);
      final items = l.items;
      final openLines = {
        for (final i in items)
          if (!i.done) i.line,
      };
      bool hasOpenChild(ListItem i) =>
          openLines.any((o) => o > i.line && o < i.end);
      // Erledigte Einträge samt Unterzeilen, außer sie enthalten noch offene
      // Unteraufgaben; überlappende Bereiche zusammenfassen, von hinten
      // löschen.
      final done = [
        for (final i in items)
          if (i.done && !hasOpenChild(i)) i,
      ];
      final kept = [
        for (final i in items)
          if (i.done && hasOpenChild(i)) i.text,
      ];
      final ranges = <(int, int)>[];
      for (final i in done) {
        if (ranges.isNotEmpty && i.line < ranges.last.$2) continue;
        ranges.add((i.line, i.end));
      }
      for (final (start, end) in ranges.reversed) {
        l.doc.remove(start, end);
      }
      if (done.isNotEmpty) await env.save(l);
      return jsonOutcome({
        'list': def.name,
        'removed': done.length,
        if (kept.isNotEmpty) 'kept': kept,
      }, summary: '${def.name}: ${done.length} erledigte entfernt');
    });
  }

  @override
  String describe(ToolArgs args) =>
      'Erledigte Einträge von ${args.requireString('list')} löschen';

  @override
  String get fallbackDescription => 'Erledigte Einträge löschen';
}
