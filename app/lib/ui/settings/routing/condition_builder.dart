import 'package:flutter/material.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import '../../design/design.dart';
import 'routing_texts.dart';

// Condition „Baukasten“ of the rule editor: a group (und/oder) of
// conditions and at most one more level of groups. Each condition and
// sub-group can be negated (nicht). Deeper trees (from an import) are not
// editable here; the editor shows them as text and keeps them.

/// One editable condition or group.
sealed class ConditionNode {
  ConditionNode({this.negated = false});

  /// Stable key for the widgets of this node.
  final Key key = UniqueKey();

  /// `nicht`.
  bool negated;

  /// The condition, or a German error text.
  (Condition?, String?) build();
}

/// Types offered in the builder (JSON names, no `and`/`or`/`not`).
const leafTypes = [
  'prefix',
  'keyword',
  'privacy',
  'regex',
  'network',
  'needsTool',
  'language',
  'sttConfidence',
  'inputLength',
  'hasImage',
  'timeWindow',
];

/// A single condition with its raw input.
final class LeafNode extends ConditionNode {
  /// Creates a condition of [type] (`keyword` by default, empty).
  LeafNode({
    this.type = 'keyword',
    this.text = '',
    this.network = NetworkState.offline,
    Set<int>? days,
    this.start = '22:00',
    this.end = '06:00',
    super.negated,
  }) : days = days ?? {};

  /// The input of [condition] (not `and`/`or`/`not`).
  factory LeafNode.of(Condition condition, {bool negated = false}) {
    final node = LeafNode(type: condition.type, negated: negated);
    switch (condition) {
      case KeywordCondition(:final words) ||
          PrefixCondition(:final words) ||
          PrivacyCondition(:final words):
        node.text = words.join(', ');
      case RegexCondition(:final pattern):
        node.text = pattern;
      case LanguageCondition(:final languages):
        node.text = languages.join(', ');
      case SttConfidenceCondition(:final below):
        node.text = '$below';
      case InputLengthCondition(:final above):
        node.text = '$above';
      case NeedsToolCondition(:final category):
        node.text = category;
      case NetworkCondition(:final state):
        node.network = state;
      case TimeWindowCondition(:final days, :final start, :final end):
        node
          ..days = {...days}
          ..start = minutesLabel(start)
          ..end = minutesLabel(end);
      case HasImageCondition() ||
          AndCondition() ||
          OrCondition() ||
          NotCondition():
        break;
    }
    return node;
  }

  /// JSON name of the type.
  String type;

  /// Words, pattern, number or category (depending on [type]).
  String text;

  /// For `network`.
  NetworkState network;

  /// For `timeWindow`: weekdays (empty = every day).
  Set<int> days;

  /// For `timeWindow`: „HH:MM“.
  String start;

  /// For `timeWindow`: „HH:MM“.
  String end;

  /// Changes the type and clears the input.
  void changeType(String value) {
    type = value;
    text = value == 'privacy' ? PrivacyCondition.defaultWords.join(', ') : '';
  }

  List<String> get _list => [
    for (final w in text.split(','))
      if (w.trim().isNotEmpty) w.trim(),
  ];

  @override
  (Condition?, String?) build() {
    final label = conditionTypeLabel(type);
    (Condition?, String?) fail(String m) => (null, '$label: $m');
    final Condition c;
    switch (type) {
      case 'keyword' || 'prefix' || 'privacy':
        final words = _list;
        if (words.isEmpty) return fail('mindestens ein Wort eingeben.');
        c = switch (type) {
          'keyword' => KeywordCondition(words),
          'prefix' => PrefixCondition(words),
          _ => PrivacyCondition(words),
        };
      case 'regex':
        if (text.trim().isEmpty) return fail('Muster eingeben.');
        c = RegexCondition(text.trim());
      case 'language':
        if (_list.isEmpty) return fail('Sprachkürzel eingeben (de, fr …).');
        c = LanguageCondition(_list);
      case 'sttConfidence':
        final v = double.tryParse(text.trim().replaceAll(',', '.'));
        if (v == null || v <= 0 || v > 1) {
          return fail('Schwelle zwischen 0 und 1 eingeben.');
        }
        c = SttConfidenceCondition(v);
      case 'inputLength':
        final v = int.tryParse(text.trim());
        if (v == null || v < 0) return fail('Zeichenzahl eingeben.');
        c = InputLengthCondition(v);
      case 'needsTool':
        if (text.trim().isEmpty) return fail('Kategorie eingeben.');
        c = NeedsToolCondition(text.trim());
      case 'network':
        c = NetworkCondition(network);
      case 'hasImage':
        c = const HasImageCondition();
      case 'timeWindow':
        final s = _minutes(start);
        final e = _minutes(end);
        if (s == null || e == null) return fail('Uhrzeit als HH:MM eingeben.');
        c = TimeWindowCondition(days: days, start: s, end: e);
      default:
        return fail('unbekannter Typ.');
    }
    return (negated ? NotCondition(c) : c, null);
  }

  static int? _minutes(String value) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    return h > 23 || min > 59 ? null : h * 60 + min;
  }
}

/// A group: all ([any] false, `und`) or one ([any] true, `oder`) of
/// [children].
final class GroupNode extends ConditionNode {
  /// Creates a group.
  GroupNode({this.any = false, List<ConditionNode>? children, super.negated})
    : children = children ?? [];

  /// `oder` instead of `und`.
  bool any;

  /// Conditions and (in the root only) sub-groups.
  final List<ConditionNode> children;

  @override
  (Condition?, String?) build() {
    if (children.isEmpty) return (null, 'Eine Gruppe ist leer.');
    final parts = <Condition>[];
    for (final child in children) {
      final (c, error) = child.build();
      if (error != null) return (null, error);
      parts.add(c!);
    }
    final Condition c = parts.length == 1
        ? parts.single
        : any
        ? OrCondition(parts)
        : AndCondition(parts);
    return (negated ? NotCondition(c) : c, null);
  }
}

/// Most group levels the builder edits (root plus one).
const maxGroupDepth = 2;

/// The editable tree of [condition], or `null` if it is nested deeper
/// than the builder can edit ([maxGroupDepth]).
GroupNode? editableTree(Condition condition) => switch (condition) {
  AndCondition(:final conditions) => _group(conditions, any: false, depth: 1),
  OrCondition(:final conditions) => _group(conditions, any: true, depth: 1),
  _ => switch (_node(condition, 1)) {
    final node? => GroupNode(children: [node]),
    null => null,
  },
};

GroupNode? _group(
  List<Condition> conditions, {
  required bool any,
  required int depth,
}) {
  final children = <ConditionNode>[];
  for (final c in conditions) {
    final node = _node(c, depth);
    if (node == null) return null;
    children.add(node);
  }
  return GroupNode(any: any, children: children);
}

/// [c] as a child of a group at [depth].
ConditionNode? _node(Condition c, int depth) {
  switch (c) {
    case NotCondition(:final condition):
      final inner = _node(condition, depth);
      if (inner == null || inner.negated) return null;
      return inner..negated = true;
    case AndCondition(:final conditions) || OrCondition(:final conditions):
      if (depth >= maxGroupDepth) return null;
      return _group(conditions, any: c is OrCondition, depth: depth + 1);
    case _:
      return LeafNode.of(c);
  }
}

/// The builder for [root]; [onChanged] runs after every edit.
class ConditionBuilder extends StatelessWidget {
  /// Creates the builder.
  const ConditionBuilder({
    super.key,
    required this.root,
    required this.onChanged,
  });

  /// The tree being edited.
  final GroupNode root;

  /// Called after every change (the editor rebuilds).
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) =>
      _GroupEditor(group: root, isRoot: true, onChanged: onChanged);
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    super.key,
    required this.group,
    required this.isRoot,
    required this.onChanged,
    this.onRemove,
  });

  final GroupNode group;
  final bool isRoot;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  Widget _head() => Wrap(
    spacing: WSpace.s,
    runSpacing: WSpace.s,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(isRoot ? 'Es gilt' : 'Gruppe', style: WText.detail),
      ChoiceChip(
        label: const Text('alle (und)'),
        selected: !group.any,
        onSelected: (_) {
          group.any = false;
          onChanged();
        },
      ),
      ChoiceChip(
        label: const Text('eine (oder)'),
        selected: group.any,
        onSelected: (_) {
          group.any = true;
          onChanged();
        },
      ),
      if (!isRoot)
        FilterChip(
          label: const Text('nicht'),
          selected: group.negated,
          onSelected: (v) {
            group.negated = v;
            onChanged();
          },
        ),
    ],
  );

  Widget _addButtons() => Wrap(
    spacing: WSpace.s,
    children: [
      TextButton(
        onPressed: () {
          group.children.add(LeafNode());
          onChanged();
        },
        child: Text(isRoot ? '+ Bedingung' : '+ Bedingung in Gruppe'),
      ),
      if (isRoot)
        TextButton(
          onPressed: () {
            group.children.add(
              GroupNode(any: !group.any, children: [LeafNode()]),
            );
            onChanged();
          },
          child: const Text('+ Gruppe'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [
        Row(
          children: [
            Expanded(child: _head()),
            if (onRemove != null)
              WIconButton(
                icon: WIcons.close,
                tooltip: 'Gruppe entfernen',
                shape: WIconButtonShape.round,
                iconSize: WSize.iconSmall,
                onPressed: onRemove,
              ),
          ],
        ),
        for (final child in group.children)
          switch (child) {
            final LeafNode leaf => _LeafEditor(
              key: leaf.key,
              node: leaf,
              onChanged: onChanged,
              onRemove: () {
                group.children.remove(leaf);
                onChanged();
              },
            ),
            final GroupNode sub => _GroupEditor(
              key: sub.key,
              group: sub,
              isRoot: false,
              onChanged: onChanged,
              onRemove: () {
                group.children.remove(sub);
                onChanged();
              },
            ),
          },
        _addButtons(),
      ],
    );
    if (isRoot) return body;
    return Container(
      padding: const EdgeInsets.all(WSpace.m),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WRadius.button),
        border: Border.all(color: WColors.line, width: WSize.border),
      ),
      child: body,
    );
  }
}

class _LeafEditor extends StatelessWidget {
  const _LeafEditor({
    super.key,
    required this.node,
    required this.onChanged,
    required this.onRemove,
  });

  final LeafNode node;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final (_, error) = node.build();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WSpace.m,
        WSpace.xs,
        WSpace.xs,
        WSpace.m,
      ),
      decoration: BoxDecoration(
        color: WColors.surfaceRaised,
        borderRadius: BorderRadius.circular(WRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WSpace.xs,
        children: [
          Row(
            spacing: WSpace.s,
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: node.type,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  style: WText.body,
                  dropdownColor: WColors.surfaceRaised,
                  items: [
                    for (final t in leafTypes)
                      DropdownMenuItem(
                        value: t,
                        child: Text(conditionTypeLabel(t)),
                      ),
                  ],
                  onChanged: (t) {
                    if (t == null || t == node.type) return;
                    node.changeType(t);
                    onChanged();
                  },
                ),
              ),
              FilterChip(
                label: const Text('nicht'),
                selected: node.negated,
                onSelected: (v) {
                  node.negated = v;
                  onChanged();
                },
              ),
              WIconButton(
                icon: WIcons.close,
                tooltip: 'Bedingung entfernen',
                shape: WIconButtonShape.round,
                iconSize: WSize.iconSmall,
                onPressed: onRemove,
              ),
            ],
          ),
          ..._input(),
          if (error != null)
            Text(error, style: WText.detail.copyWith(color: WColors.warn)),
        ],
      ),
    );
  }

  Widget _networkChips() => Wrap(
    spacing: WSpace.s,
    children: [
      for (final s in NetworkState.values)
        ChoiceChip(
          label: Text(switch (s) {
            NetworkState.offline => 'offline',
            NetworkState.online => 'online',
            NetworkState.metered => 'mobile Daten',
          }),
          selected: node.network == s,
          onSelected: (_) {
            node.network = s;
            onChanged();
          },
        ),
    ],
  );

  List<Widget> _timeWindow() => [
    Wrap(
      spacing: WSpace.xs,
      runSpacing: WSpace.xs,
      children: [
        for (var d = DateTime.monday; d <= DateTime.sunday; d++)
          FilterChip(
            label: Text(weekdayLabels[d - 1]),
            selected: node.days.contains(d),
            onSelected: (on) {
              on ? node.days.add(d) : node.days.remove(d);
              onChanged();
            },
          ),
      ],
    ),
    Row(
      spacing: WSpace.s,
      children: [
        Expanded(
          child: TextFormField(
            key: ValueKey('${node.key}-start'),
            initialValue: node.start,
            decoration: const InputDecoration(labelText: 'von (HH:MM)'),
            onChanged: (v) {
              node.start = v;
              onChanged();
            },
          ),
        ),
        Expanded(
          child: TextFormField(
            key: ValueKey('${node.key}-end'),
            initialValue: node.end,
            decoration: const InputDecoration(labelText: 'bis (HH:MM)'),
            onChanged: (v) {
              node.end = v;
              onChanged();
            },
          ),
        ),
      ],
    ),
  ];

  List<Widget> _input() {
    Widget field(String label, {String? hint, TextInputType? keyboard}) =>
        TextFormField(
          key: ValueKey('${node.key}-${node.type}'),
          initialValue: node.text,
          keyboardType: keyboard,
          style: node.type == 'regex' ? WText.mono : WText.body,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (v) {
            node.text = v;
            onChanged();
          },
        );
    return switch (node.type) {
      'keyword' || 'privacy' => [
        field('Wörter, durch Komma getrennt', hint: 'privat, vertraulich'),
      ],
      'prefix' => [
        field('Wörter am Satzanfang, durch Komma getrennt', hint: 'Claude'),
      ],
      'regex' => [field('Muster (auf normalisiertem Text)', hint: r'\bdenk\b')],
      'language' => [field('Sprachen', hint: 'de, fr')],
      'sttConfidence' => [
        field(
          'Sicherheit unter',
          hint: '0.6',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
      'inputLength' => [
        field('Mehr Zeichen als', hint: '280', keyboard: TextInputType.number),
      ],
      'needsTool' => [field('Kategorie', hint: 'obsidian.edit')],
      'network' => [_networkChips()],
      'timeWindow' => _timeWindow(),
      _ => const [],
    };
  }
}
