import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import '../../../di/providers.dart';
import '../../../di/routing.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'condition_builder.dart';
import 'routing_texts.dart';
import 'target_picker.dart';

/// Routing → Regel bearbeiten: name, on/off, target (profile + model),
/// `stripTrigger` and the condition builder. Warnings of the rule set
/// (`RuleSetIssue`) for this rule show live.
class RuleEditorScreen extends ConsumerStatefulWidget {
  /// Edits rule [ruleId]; `null` creates a new rule.
  const RuleEditorScreen({super.key, this.ruleId});

  /// Rule to edit, `null` = new.
  final String? ruleId;

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  late final RoutingState _state = ref.read(routingProvider).requireValue;
  late final RoutingRule? _existing = _state.rules!.rules
      .where((r) => r.id == widget.ruleId)
      .firstOrNull;
  late final String _id = _existing?.id ?? ref.read(idGeneratorProvider).next();
  late final _name = TextEditingController(text: _existing?.name ?? '');
  late bool _enabled = _existing?.enabled ?? true;
  late bool _strip = _existing?.stripTrigger ?? false;
  late RouteTarget _target = _existing?.target ?? _state.rules!.defaultTarget;

  /// The editable tree; `null` while a deeper imported condition is kept.
  late GroupNode? _tree = _existing == null
      ? GroupNode(children: [LeafNode(type: 'prefix')])
      : editableTree(_existing.condition);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The rule as edited, or a German error.
  (RoutingRule?, String?) _draft() {
    final name = _name.text.trim();
    if (name.isEmpty) return (null, context.l10n.ruleEditorNeedName);
    if (_target.modelId.isEmpty) {
      return (null, context.l10n.ruleEditorNeedModel);
    }
    final Condition condition;
    if (_tree case final tree?) {
      final (c, error) = tree.build(context.l10n);
      if (error != null) return (null, error);
      condition = c!;
    } else {
      condition = _existing!.condition;
    }
    return (
      RoutingRule(
        id: _id,
        name: name,
        enabled: _enabled,
        condition: condition,
        target: _target,
        stripTrigger: _strip,
        aliases: _existing?.aliases ?? const [],
      ),
      null,
    );
  }

  RuleSet _with(RoutingRule rule) {
    final rules = _state.rules!;
    final list = [...rules.rules];
    final i = list.indexWhere((r) => r.id == rule.id);
    if (i < 0) {
      list.add(rule);
    } else {
      list[i] = rule;
    }
    return rules.copyWith(rules: list);
  }

  Future<void> _save(RoutingRule rule) async {
    setState(() => _saving = true);
    await ref.read(routingProvider.notifier).save(_with(rule));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: context.l10n.ruleEditorDeleteTitle(_existing!.name),
      message: context.l10n.ruleEditorDeleteBody,
      yes: context.l10n.delete,
    );
    if (!ok || !mounted) return;
    final rules = _state.rules!;
    await ref
        .read(routingProvider.notifier)
        .save(
          rules.copyWith(
            rules: [
              for (final r in rules.rules)
                if (r.id != _existing.id) r,
            ],
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _ruleSection() => SettingsSection(
    title: context.l10n.ruleEditorRule,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(WSpace.l, WSpace.s, WSpace.l, 0),
        child: TextField(
          controller: _name,
          style: WText.body,
          decoration: InputDecoration(labelText: context.l10n.name),
          onChanged: (_) => setState(() {}),
        ),
      ),
      SettingsRow(
        title: context.l10n.ruleEditorActive,
        trailing: WSwitch(
          value: _enabled,
          semanticLabel: context.l10n.ruleEditorActiveLabel,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ),
      SettingsRow(
        title: context.l10n.ruleEditorStripTrigger,
        detail: context.l10n.ruleEditorStripTriggerHint,
        trailing: WSwitch(
          value: _strip,
          semanticLabel: context.l10n.ruleEditorStripTriggerLabel,
          onChanged: (v) => setState(() => _strip = v),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final (draft, error) = _draft();
    final issues = draft == null
        ? const <RuleSetIssue>[]
        : validateRuleSet(
            _with(draft),
            _state.routingProfiles,
          ).where((i) => i.ruleId == _id).toList();
    return SettingsPage(
      title: _existing == null
          ? context.l10n.ruleEditorNewRule
          : context.l10n.ruleEditorEditRule,
      children: [
        _ruleSection(),
        SettingsSection(
          title: context.l10n.ruleEditorTarget,
          children: [
            Padding(
              padding: const EdgeInsets.all(WSpace.l),
              child: TargetPicker(
                profiles: _state.profiles,
                value: _target,
                onChanged: (t) => setState(() => _target = t),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: context.l10n.ruleEditorCondition,
          children: [
            Padding(
              padding: const EdgeInsets.all(WSpace.l),
              child: switch (_tree) {
                final tree? => ConditionBuilder(
                  root: tree,
                  onChanged: () => setState(() {}),
                ),
                null => _DeepCondition(
                  condition: _existing!.condition,
                  onRebuild: () =>
                      setState(() => _tree = GroupNode(children: [LeafNode()])),
                ),
              },
            ),
          ],
        ),
        if (issues.isNotEmpty || error != null)
          IssueList([?error, for (final i in issues) i.message]),
        PrimaryButton(
          context.l10n.save,
          onPressed: draft == null || _saving
              ? null
              : () => unawaited(_save(draft)),
        ),
        if (_existing != null)
          WideButton(
            context.l10n.ruleEditorDeleteRule,
            onPressed: _saving ? null : () => unawaited(_delete()),
          ),
      ],
    );
  }
}

/// A condition nested deeper than the builder edits (from an import):
/// shown as text, kept unless the user rebuilds it.
class _DeepCondition extends StatelessWidget {
  const _DeepCondition({required this.condition, required this.onRebuild});

  final Condition condition;
  final VoidCallback onRebuild;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WSpace.s,
    children: [
      Text(describeCondition(context.l10n, condition), style: WText.mono),
      Text(context.l10n.ruleEditorTooDeep, style: WText.detail),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: onRebuild,
          child: Text(context.l10n.ruleEditorRebuild),
        ),
      ),
    ],
  );
}

/// Warnings in a card: yellow triangle + text per line.
class IssueList extends StatelessWidget {
  /// Creates the list.
  const IssueList(this.messages, {super.key});

  /// German texts.
  final List<String> messages;

  @override
  Widget build(BuildContext context) => SectionCard(
    children: [
      for (final m in messages)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WSpace.l,
            vertical: WSpace.m,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WSpace.s10,
            children: [
              const CheckStatusIcon(CheckStatus.pending),
              Expanded(child: Text(m, style: WText.detail)),
            ],
          ),
        ),
    ],
  );
}
