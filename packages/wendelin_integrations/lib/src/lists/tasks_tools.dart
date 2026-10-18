import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/time.dart';
import '../common/tool_args.dart';
import 'lists.dart';
import 'lists_write_tools.dart';
import 'task_format.dart';

/// Tasks: due dates and priorities on the lists (`tasks__…` tools). Works
/// on the same files and definitions as [ListsIntegration] (and shares its
/// per-file write queue).
final class TasksIntegration implements Integration {
  /// Creates the integration; [definitions] returns the lists currently
  /// configured in the settings (read on every tool call).
  TasksIntegration(
    ListFilePort port, {
    required List<ListDefinition> Function() definitions,
  }) : env = ListsEnv(port, definitions);

  /// Shared tool state.
  final ListsEnv env;

  @override
  String get id => 'tasks';

  @override
  String get displayName => 'Aufgaben';

  @override
  String get iconId => 'task';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: ListsIntegration.defineStep,
      kind: SetupStepKind.config,
      label: 'Liste anlegen und Datei wählen',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [if (env.definitions().isEmpty) ListsIntegration.defineStep],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    TasksAddTool(env),
    TasksListTool(env),
    TasksCompleteTool(env),
  ]);
}

const _taskListProp = {
  'type': 'string',
  'description':
      'List name as the user says it; omit to use the default task list.',
};

/// Sort rank: highest > high > medium > normal (none) > low > lowest.
int _rank(TaskPriority? p) => switch (p) {
  TaskPriority.highest => 0,
  TaskPriority.high => 1,
  TaskPriority.medium => 2,
  null => 3,
  TaskPriority.low => 4,
  TaskPriority.lowest => 5,
};

LocalDate _today(ToolContext ctx) =>
    LocalDate.of(ctx.clock.now(), timeZoneLocation(ctx.timeZone));

/// `tasks__add` (write; undo removes the added line).
final class TasksAddTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool.
  const TasksAddTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'tasks__add';

  @override
  String get description =>
      'Add a task, optionally with due date (and time) and priority, to a '
      'task list (default list if none named). Stored as Markdown task with '
      'Obsidian Tasks markers. Example: title "Steuer abgeben", due '
      '"2026-10-20", priority "high".';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'The task, without dates.'},
      'list': _taskListProp,
      'due': {
        'type': 'string',
        'description':
            'Due date 2026-10-20, or with time 2026-10-20T14:30 (device '
            'time zone). Resolve "tomorrow" etc. before the call.',
      },
      'priority': {
        'type': 'string',
        'enum': ['highest', 'high', 'medium', 'low', 'lowest'],
        'description': 'Omit for normal priority.',
      },
    },
    'required': ['title'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  ({String text, String title}) _compose(ToolArgs args) {
    final title = args.requireString('title');
    if (title.contains('\n') || title.contains('\r')) {
      throw const InvalidArgumentsException('„title“ ohne Zeilenumbruch');
    }
    for (final m in taskMarkers) {
      if (title.contains(m)) {
        throw InvalidArgumentsException(
          '„title“ darf keine Aufgaben-Marke wie $m enthalten; Datum, Uhrzeit '
          'und Priorität gehören in „due“ und „priority“',
        );
      }
    }
    final dueRaw = args.optString('due');
    IsoInput? iso;
    if (dueRaw != null && dueRaw.isNotEmpty) {
      iso = IsoInput.parse(dueRaw, 'due');
      if (iso.offset != null) {
        throw InvalidArgumentsException(
          '„due“ ohne Zeitzone angeben (Ortszeit des Geräts, z. B. '
          '2026-10-20T14:30; war „$dueRaw“)',
        );
      }
    }
    final prioRaw = args.optString('priority');
    TaskPriority? prio;
    if (prioRaw != null && prioRaw.isNotEmpty) {
      prio = TaskPriority.byId(prioRaw.toLowerCase());
      if (prio == null) {
        throw InvalidArgumentsException(
          '„priority“ muss highest, high, medium, low oder lowest sein '
          '(war „$prioRaw“)',
        );
      }
    }
    return (
      title: title,
      text: composeTask(
        title,
        due: iso?.date,
        minutes: iso?.minutes,
        priority: prio,
      ),
    );
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final task = _compose(args);
    final def = env.resolveTaskList(args.optString('list'), write: true);
    return env.exclusive(
      def.target,
      () => AddItemsTool(env).add(def, [task.text]),
    );
  }

  @override
  String describe(ToolArgs args) => 'Aufgabe „${_compose(args).text}“ anlegen';

  @override
  String get fallbackDescription => 'Aufgabe anlegen';
}

/// `tasks__list` (read).
final class TasksListTool extends IntegrationTool {
  /// Creates the tool.
  const TasksListTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'tasks__list';

  @override
  String get description =>
      'Show tasks with due date and priority. filter: today (due today), '
      'overdue (due before today), all (default; open tasks). Without list: '
      'all lists. Sorted by due date, then priority.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'filter': {
        'type': 'string',
        'enum': ['today', 'overdue', 'all'],
        'description': 'today = due today, overdue = due before today.',
      },
      'list': {
        'type': 'string',
        'description': 'List name; omit for all lists.',
      },
      'include_done': {
        'type': 'boolean',
        'description': 'Also show checked tasks (default false).',
      },
    },
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final filter = args.optString('filter') ?? 'all';
    if (!const {'today', 'overdue', 'all'}.contains(filter)) {
      throw InvalidArgumentsException(
        '„filter“ muss today, overdue oder all sein (war „$filter“)',
      );
    }
    final withDone = args.optBool('include_done') ?? false;
    final query = args.optString('list');
    final defs = query == null || query.isEmpty
        ? env.definitions()
        : [env.resolve(query, write: false)];
    if (defs.isEmpty) env.resolve('', write: false);
    final today = _today(ctx);
    final rows = <({TaskInfo info, bool done, String list})>[];
    final errors = <Map<String, Object?>>[];
    for (final d in defs) {
      try {
        for (final i in (await env.load(d)).items) {
          final info = TaskInfo.parse(i.text);
          if (i.done && !withDone) continue;
          final due = info.due;
          final keep = switch (filter) {
            'today' => due == today,
            'overdue' => due != null && due.compareTo(today) < 0 && !i.done,
            _ => true,
          };
          if (keep) rows.add((info: info, done: i.done, list: d.name));
        }
      } on PortException catch (e) {
        errors.add({'list': d.name, 'error': e.message});
      }
    }
    int cmp(
      ({TaskInfo info, bool done, String list}) a,
      ({TaskInfo info, bool done, String list}) b,
    ) {
      final ad = a.info.due, bd = b.info.due;
      if (ad != bd) {
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      }
      final am = a.info.minutes ?? 24 * 60, bm = b.info.minutes ?? 24 * 60;
      if (am != bm) return am.compareTo(bm);
      return _rank(a.info.priority).compareTo(_rank(b.info.priority));
    }

    rows.sort(cmp);
    return ToolOutcome.text(
      '$listDataNotice\n${jsonEncode({
        'filter': filter,
        'today': today.toIso(),
        'tasks': [
          for (final r in rows) {'title': r.info.title, 'list': r.list, if (r.info.due != null) 'due': r.info.due!.toIso(), if (r.info.minutes != null) 'time': formatMinutes(r.info.minutes!), if (r.info.priority != null) 'priority': r.info.priority!.id, if (r.info.due != null && r.info.due!.compareTo(today) < 0 && !r.done) 'overdue': true, if (r.done) 'done': true},
        ],
        if (errors.isNotEmpty) 'errors': errors,
      })}',
      summary: '${rows.length} Aufgaben',
    );
  }

  @override
  String describe(ToolArgs args) => 'Aufgaben anzeigen';

  @override
  String get fallbackDescription => 'Aufgaben anzeigen';
}

/// `tasks__complete` (write; undo restores the original line).
final class TasksCompleteTool extends IntegrationTool {
  /// Creates the tool.
  const TasksCompleteTool(this.env);

  /// Shared state.
  final ListsEnv env;

  @override
  String get name => 'tasks__complete';

  @override
  String get description =>
      'Mark a task as done (adds the completion date ✅). Example: title '
      '"Steuer". Default task list if none named.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'title': {
        'type': 'string',
        'description': 'The task, roughly as written.',
      },
      'list': _taskListProp,
    },
    'required': ['title'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.requireString('title');
    final def = env.resolveTaskList(args.optString('list'), write: true);
    final today = _today(ctx);
    return env.exclusive(def.target, () async {
      final l = await env.load(def);
      final item = pickItem(
        query,
        l.items,
        def.name,
        write: false,
        textOf: (i) => TaskInfo.parse(i.text).title,
      );
      final title = TaskInfo.parse(item.text).title;
      if (item.done) {
        return jsonOutcome({
          'list': def.name,
          'already_done': title,
        }, summary: '$title war schon erledigt');
      }
      final original = l.doc.lines[item.line].text;
      l.doc.setDone(item.line, true);
      if (TaskInfo.parse(item.text).completed == null) {
        l.doc.lines[item.line].text =
            '${l.doc.lines[item.line].text.trimRight()} ✅ ${today.toIso()}';
      }
      final changed = l.doc.lines[item.line].text;
      await env.save(l);
      return jsonOutcome(
        {'list': def.name, 'completed': title},
        summary: '${def.name}: $title erledigt',
        undo: UndoAction(
          label: 'Wieder offen',
          run: () => env.exclusive(def.target, () async {
            final fresh = await env.load(def);
            final r = fresh.range;
            final i = r == null
                ? null
                : fresh.doc.findLine(
                    changed,
                    item.line,
                    from: r.start,
                    to: r.end,
                  );
            if (i == null) {
              throw const PortException(
                PortErrorKind.notFound,
                'Rückgängig nicht möglich: Die Aufgabe wurde inzwischen '
                'geändert oder entfernt',
              );
            }
            fresh.doc.lines[i].text = original;
            await env.save(fresh);
          }),
        ),
      );
    });
  }

  @override
  String describe(ToolArgs args) =>
      'Aufgabe „${args.requireString('title')}“ '
      'abhaken';

  @override
  String get fallbackDescription => 'Aufgabe abhaken';
}
