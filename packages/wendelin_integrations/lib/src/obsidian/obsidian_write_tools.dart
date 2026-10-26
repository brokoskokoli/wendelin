import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/time.dart';
import '../common/tool_args.dart';
import '../markdown/markdown_doc.dart';
import 'daily_notes.dart';
import 'line_diff.dart';
import 'obsidian_integration.dart';
import 'obsidian_tool_support.dart';
import 'vault_path.dart';

/// `obsidian__create_note` (write; undo deletes the note if unchanged).
final class CreateNoteTool extends IntegrationTool
    implements FixedConfirmationTool, NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const CreateNoteTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  @override
  String get name => 'obsidian__create_note';

  @override
  String get description =>
      'Create a new Obsidian note. Fails if it already exists. Example: '
      'path "Ideen/Gartenhaus", content "- Holz bestellen".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'path': pathProp,
      'content': {'type': 'string', 'description': 'Markdown text.'},
    },
    'required': ['path'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Set<String> get confirmationKeys => const {'note.created'};

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final path = VaultPath.newNote(args.requireString('path'));
    final lines = textLines(args, 'content', allowEmpty: true);
    final content = lines.isEmpty ? '' : '${lines.join('\n')}\n';
    return env.exclusive(path, () async {
      env.markDirty();
      await env.vault.create(path, content);
      return jsonOutcome(
        {'created': path},
        summary: 'Notiz angelegt: ${VaultPath.title(path)}',
        fixed: ConfirmationSentence('note.created', {
          'note': VaultPath.title(path),
        }),
        undo: UndoAction(
          label: 'Notiz löschen',
          run: () => env.exclusive(path, () async {
            final now = await env.vault.read(path);
            if (now != content) {
              throw const PortException(
                PortErrorKind.rejected,
                'Rückgängig nicht möglich: Die Notiz wurde inzwischen '
                'geändert',
              );
            }
            env.markDirty();
            await env.vault.delete(path);
          }),
        ),
      );
    });
  }

  @override
  String describe(ToolArgs args) =>
      'Notiz „${args.requireString('path')}“ anlegen';

  @override
  String get fallbackDescription => 'Notiz anlegen';
}

/// `obsidian__append_to_note` (write; undo removes the appended lines).
final class AppendToNoteTool extends IntegrationTool
    implements FixedConfirmationTool, NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const AppendToNoteTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  @override
  String get name => 'obsidian__append_to_note';

  @override
  String get description =>
      'Append text to an existing Obsidian note, optionally at the end of '
      'the section below a heading (created if missing). Example: path '
      '"Projekte/Wendelin", heading "Ideen", text "- Offline-Modus".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'path': pathProp,
      'text': {'type': 'string', 'description': 'Markdown text to append.'},
      'heading': {
        'type': 'string',
        'description': 'Append below this heading instead of at the end.',
      },
    },
    'required': ['path', 'text'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Set<String> get confirmationKeys => const {'note.appended'};

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final text = textLines(args, 'text');
    final heading = args.optString('heading');
    final path = await env.resolveNote(
      args.requireString('path'),
      write: true,
      now: ctx.clock.now(),
    );
    return env.exclusive(path, () async {
      final note = await env.load(path);
      final plan = appendPlan(
        env,
        note,
        heading == null || heading.isEmpty ? null : heading,
        text,
      );
      note.doc.insert(plan.at, plan.block);
      await env.save(note);
      return jsonOutcome(
        {
          'note': path,
          'appended_lines': text.length,
          if (plan.createdHeading != null)
            'created_heading': plan.createdHeading,
        },
        summary: 'An ${VaultPath.title(path)} angehängt: ${excerpt(text)}',
        fixed: ConfirmationSentence('note.appended', {
          'note': VaultPath.title(path),
        }),
        undo: removeBlockUndo(env, path, plan.block, plan.at),
      );
    });
  }

  @override
  String describe(ToolArgs args) {
    final h = args.optString('heading');
    return 'An Notiz „${args.requireString('path')}“ anhängen'
        '${h == null || h.isEmpty ? '' : ' (unter „$h“)'}';
  }

  @override
  String get fallbackDescription => 'An Notiz anhängen';
}

/// `obsidian__append_daily_note` (write; creates the daily note from the
/// template if missing; undo removes the text or the new note).
final class AppendDailyNoteTool extends IntegrationTool
    implements FixedConfirmationTool, NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const AppendDailyNoteTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  @override
  String get name => 'obsidian__append_daily_note';

  @override
  String get description =>
      'Append text to the daily note (today or a given date), created from '
      'the user\'s template if missing. Example: text "- Zahnarzt angerufen", '
      'date "2026-10-15", heading "Log".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Markdown text to append.'},
      'date': {
        'type': 'string',
        'description': 'Day as YYYY-MM-DD, e.g. 2026-10-15; default today.',
      },
      'heading': {
        'type': 'string',
        'description': 'Append below this heading (created if missing).',
      },
    },
    'required': ['text'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Set<String> get confirmationKeys => const {'note.appended'};

  LocalDate _date(ToolArgs args, ToolContext ctx) {
    final raw = args.optString('date');
    if (raw != null && raw.isNotEmpty) {
      final iso = IsoInput.parse(raw, 'date');
      if (iso.hasTime) {
        throw const InvalidArgumentsException('„date“ ohne Uhrzeit angeben');
      }
      return iso.date;
    }
    return LocalDate.of(ctx.clock.now(), timeZoneLocation(ctx.timeZone));
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final text = textLines(args, 'text');
    final heading = args.optString('heading');
    final date = _date(args, ctx);
    final settings = env.settings();
    final daily = settings.dailyNotes;
    final path = daily.pathFor(date, locale: settings.locale);
    final now = tzNow(ctx);
    return env.exclusive(path, () async {
      final existed = await env.vault.exists(path);
      var templateMissing = false;
      LoadedNote note;
      if (existed) {
        note = await env.load(path);
      } else {
        var content = '';
        final template = daily.template;
        if (template != null && template.trim().isNotEmpty) {
          final t = VaultPath.note(template);
          if (await env.vault.exists(t)) {
            content = fillTemplate(
              (await env.load(t)).doc.toString(),
              title: VaultPath.title(path),
              date: date,
              minutes: now.hour * 60 + now.minute,
              locale: settings.locale,
            );
          } else {
            templateMissing = true;
          }
        }
        note = LoadedNote(path, MarkdownDoc.parse(content, setext: true));
      }
      final plan = appendPlan(
        env,
        note,
        heading == null || heading.isEmpty ? null : heading,
        text,
      );
      note.doc.insert(plan.at, plan.block);
      final written = note.doc.toString();
      if (existed) {
        await env.save(note);
      } else {
        env.markDirty();
        await env.vault.create(path, written);
      }
      final blockUndo = removeBlockUndo(env, path, plan.block, plan.at);
      return jsonOutcome(
        {
          'note': path,
          if (!existed) 'created': true,
          if (templateMissing) 'template_missing': daily.template,
          if (plan.createdHeading != null)
            'created_heading': plan.createdHeading,
        },
        summary: 'Tagesnotiz ${date.toIso()}: ${excerpt(text)}',
        fixed: ConfirmationSentence('note.appended', {
          'note': VaultPath.title(path),
        }),
        undo: existed
            ? blockUndo
            : UndoAction(
                label: 'Text entfernen',
                run: () async {
                  // Neu angelegte, unveränderte Tagesnotiz ganz löschen,
                  // sonst nur den eingefügten Text entfernen.
                  final deleted = await env.exclusive(path, () async {
                    if (await env.vault.read(path) != written) return false;
                    env.markDirty();
                    await env.vault.delete(path);
                    return true;
                  });
                  if (!deleted) await blockUndo();
                },
              ),
      );
    });
  }

  @override
  String describe(ToolArgs args) {
    final d = args.optString('date');
    return 'An Tagesnotiz${d == null || d.isEmpty ? '' : ' $d'} anhängen';
  }

  @override
  String get fallbackDescription => 'An Tagesnotiz anhängen';
}

/// Wall-clock time of the context's clock in the context's zone.
tz.TZDateTime tzNow(ToolContext ctx) =>
    tz.TZDateTime.from(ctx.clock.now(), timeZoneLocation(ctx.timeZone));

/// `obsidian__replace_section` (external: always confirmed; the
/// confirmation shows a diff prepared live).
final class ReplaceSectionTool extends IntegrationTool
    implements ConfirmationPreparer, NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const ReplaceSectionTool(this.env);

  /// Shared state.
  final ObsidianEnv env;

  @override
  String get name => 'obsidian__replace_section';

  @override
  String get description =>
      'Replace the text below a heading of an Obsidian note (up to the next '
      'heading; sub-sections stay). The user confirms a diff. Example: path '
      '"Projekte/Wendelin", heading "Status", content "Läuft."';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'path': pathProp,
      'heading': {'type': 'string', 'description': 'Heading of the section.'},
      'content': {
        'type': 'string',
        'description': 'New Markdown text of the section, without heading.',
      },
    },
    'required': ['path', 'heading', 'content'],
  };

  @override
  RiskLevel get risk => RiskLevel.external;

  /// The section's own content without leading/trailing blank lines.
  static ({int start, int end, MdHeading heading}) _section(
    ObsidianEnv env,
    LoadedNote note,
    String heading,
  ) {
    final doc = note.doc;
    final h = env.pickHeading(doc, heading, note.path, write: true);
    if (h == null) {
      throw PortException(
        PortErrorKind.notFound,
        'Überschrift „$heading“ gibt es in ${vaultNames([note.path])} nicht. '
        'Vorhanden: ${vaultNames(doc.headings.map((x) => x.title).take(30))}',
      );
    }
    final own = doc.ownContentOf(h);
    var start = own.start;
    final end = doc.contentEnd(own.start, own.end);
    while (start < end && doc.isBlank(start)) {
      start++;
    }
    if (end - start > maxSectionLines) {
      throw const PortException(
        PortErrorKind.rejected,
        'Abschnitt ist zu lang zum Ersetzen (höchstens $maxSectionLines '
        'Zeilen)',
      );
    }
    return (start: start, end: end, heading: h);
  }

  static String _key(String path, String heading, List<String> content) =>
      jsonEncode([path, heading, content]);

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final heading = args.requireString('heading');
    final content = textLines(args, 'content');
    if (content.length > maxSectionLines) {
      throw const InvalidArgumentsException(
        '„content“ hat zu viele Zeilen (höchstens $maxSectionLines)',
      );
    }
    final path = await env.resolveNote(
      args.requireString('path'),
      write: true,
      now: ctx.clock.now(),
    );
    return env.exclusive(path, () async {
      final note = await env.load(path);
      final doc = note.doc;
      final s = _section(env, note, heading);
      final oldTexts = [
        for (final l in doc.lines.sublist(s.start, s.end)) l.text,
      ];
      final key = _key(path, heading, content);
      final shown = env.prepared[key];
      if (shown == null) {
        // Die Bestätigung zeigte keinen Diff (Vorschau fehlgeschlagen oder
        // zu langsam): ohne gesehenen alten Stand wird nicht überschrieben.
        throw const PortException(
          PortErrorKind.rejected,
          'Die Bestätigung konnte den alten Abschnitt nicht zeigen; nichts '
          'geschrieben. Bitte erneut ausführen, damit der Nutzer die Änderung '
          'sieht.',
        );
      }
      if (shown != oldTexts.join('\n')) {
        env.prepared.remove(key);
        throw const PortException(
          PortErrorKind.rejected,
          'Der Abschnitt wurde seit der Bestätigung geändert; nichts '
          'geschrieben. Bitte erneut ausführen.',
        );
      }
      final old = [
        for (final l in doc.lines.sublist(s.start, s.end))
          MdLine(l.text, l.eol),
      ];
      doc.replace(s.start, s.end, content);
      await env.save(note);
      env.prepared.remove(key);
      return jsonOutcome(
        {
          'note': path,
          'heading': s.heading.title,
          'removed_lines': old.length,
          'new_lines': content.length,
        },
        summary:
            'Abschnitt „${s.heading.title}“ in ${VaultPath.title(path)} '
            'ersetzt',
        undo: UndoAction(
          label: 'Alten Abschnitt wiederherstellen',
          run: () => env.exclusive(path, () async {
            final fresh = await env.load(path);
            final i = fresh.doc.findBlock(content, s.start);
            if (i == null) {
              throw const PortException(
                PortErrorKind.notFound,
                'Rückgängig nicht möglich: Der neue Abschnittstext wurde '
                'inzwischen geändert',
              );
            }
            fresh.doc.restore(i, i + content.length, old);
            await env.save(fresh);
          }),
        ),
      );
    });
  }

  /// Without a prepared diff: names the section and shows the start of
  /// the new text.
  @override
  String describe(ToolArgs args) {
    final content = textLines(args, 'content');
    return 'Abschnitt „${args.requireString('heading')}“ in '
        '„${args.requireString('path')}“ ersetzen durch:\n'
        '${lineDiff(const [], content, maxLines: confirmationDiffLines)}';
  }

  /// Reads the section live and shows the change as a line diff.
  @override
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final a = ToolArgs(args);
    try {
      final heading = a.requireString('heading');
      final content = textLines(a, 'content');
      final query = a.requireString('path');
      final path = await env.resolveNote(
        query,
        write: true,
        now: ctx.clock.now(),
      );
      final note = await env.load(path);
      final s = _section(env, note, heading);
      final old = [
        for (final l in note.doc.lines.sublist(s.start, s.end)) l.text,
      ];
      if (env.prepared.length >= 20) {
        env.prepared.remove(env.prepared.keys.first);
      }
      env.prepared[_key(path, heading, content)] = old.join('\n');
      // Found under another name than asked for: say so first (B8).
      final hint = foundHint(query, path);
      return '${hint}Abschnitt „${s.heading.title}“ in „$path“ ersetzen:\n'
          '${lineDiff(old, content, maxLines: confirmationDiffLines)}';
    } on InvalidArgumentsException {
      return fallbackDescription;
    }
  }

  @override
  String get fallbackDescription => 'Notizabschnitt ersetzen';
}
