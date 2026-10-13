import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../../di/providers.dart';
import '../../../di/routing.dart';
import '../../../platform/document_text_import.dart';
import '../../design/design.dart';
import '../../routes.dart';
import '../export.dart';
import '../settings_page.dart';
import 'chain_editor_screen.dart';
import 'import_preview.dart';
import 'routing_texts.dart';
import 'rule_editor_screen.dart';
import 'target_picker.dart';

/// Picks a file and returns its text (`null` = cancelled); replaceable in
/// tests.
final routingImporterProvider = Provider<Future<String?> Function()>(
  (ref) => const DocumentTextImport().pick,
);

/// Recognizes tool categories in the test field (same as the agent).
final toolCategoryMatcherProvider = Provider<ToolCategoryMatcher>(
  (ref) => KeywordToolCategoryMatcher(),
);

/// Settings → Routing (docs/design/screens/routing): test field with the
/// rule that takes a sentence, the rule list (drag to reorder, first match
/// wins), the fixed default, the escalation chain of the default profile,
/// import/export and „+ Regel hinzufügen“.
class RoutingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const RoutingScreen({super.key});

  @override
  ConsumerState<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<RoutingScreen> {
  final _sentence = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sentence.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sentence.dispose();
    super.dispose();
  }

  RoutingNotifier get _notifier => ref.read(routingProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(routingProvider);
    final state = async.value;
    final rules = state?.rules;
    final List<Widget> children;
    if (state == null) {
      children = [
        if (async.hasError) ...[
          Text(
            'Die Regeln lassen sich nicht lesen: ${async.error}',
            style: WText.intro,
          ),
          WideButton(
            'Regeln zurücksetzen',
            onPressed: () => unawaited(_reset()),
          ),
        ] else
          Text('…', style: WText.caption),
      ];
    } else if (rules == null) {
      children = [
        Text(
          'Routing braucht einen Provider. Richte zuerst einen ein.',
          style: WText.intro,
        ),
        WideButton(
          'Provider einrichten',
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.providerSetup),
        ),
      ];
    } else {
      children = _content(state, rules);
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                WSpace.screen,
                WSpace.screenTop - WSize.tapTargetInset,
                WSpace.screen,
                WSpace.l18,
              ),
              children: [
                Row(
                  spacing: WSpace.m,
                  children: [
                    WIconButton(
                      icon: WIcons.back,
                      tooltip: 'Zurück',
                      onPressed: () => Navigator.of(context).maybePop(),
                      iconSize: WSize.iconSmall,
                    ),
                    Expanded(child: Text('Routing', style: WText.screenTitle)),
                  ],
                ),
                const SizedBox(height: WSpace.l18 - WSize.tapTargetInset),
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) const SizedBox(height: WSpace.l18),
                  child,
                ],
              ],
            ),
          ),
          if (rules != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  WSpace.screen,
                  0,
                  WSpace.screen,
                  WSpace.xl24,
                ),
                child: PrimaryButton(
                  '+ Regel hinzufügen',
                  onPressed: () => _open(const RuleEditorScreen()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _content(RoutingState state, RuleSet rules) {
    final text = _sentence.text.trim();
    final decision = text.isEmpty
        ? null
        : explain(
            rules,
            RoutingContext(
              input: UserInput(text: text),
              now: ref.read(clockProvider).now(),
              network: ref.read(networkStatusProvider).current,
              matcher: ref.read(toolCategoryMatcherProvider),
            ),
            profiles: state.routingProfiles,
          );
    final issues = state.issues;
    return [
      _TestCard(controller: _sentence, state: state, decision: decision),
      if (issues.isNotEmpty) IssueList([for (final i in issues) i.message]),
      // Every rule carries its gap below, so the default follows at the
      // same distance (the list itself has no spacing).
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Erste passende Regel gewinnt', style: WText.sectionLabel),
          const SizedBox(height: WSpace.s),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final list = [...rules.rules];
              list.insert(to, list.removeAt(from));
              unawaited(_notifier.save(rules.copyWith(rules: list)));
            },
            children: [
              for (final (i, rule) in rules.rules.indexed)
                Padding(
                  key: ValueKey(rule.id),
                  padding: const EdgeInsets.only(bottom: WSpace.s),
                  child: Opacity(
                    opacity: rule.enabled ? 1 : WOpacity.inactive,
                    child: RuleTile(
                      name: rule.enabled ? rule.name : '${rule.name} (aus)',
                      condition: describeCondition(rule.condition),
                      target: targetLabel(state, rule.target),
                      targetLevel: targetLevel(state, rule.target),
                      active: decision?.rule?.id == rule.id,
                      reorderIndex: i,
                      handleLabel: 'Regel „${rule.name}“ verschieben',
                      onTap: () => _open(RuleEditorScreen(ruleId: rule.id)),
                    ),
                  ),
                ),
            ],
          ),
          RuleTile(
            name: 'Default',
            condition: 'immer',
            target: targetLabel(state, rules.defaultTarget),
            targetLevel: targetLevel(state, rules.defaultTarget),
            isDefault: true,
            active: decision != null && decision.rule == null,
            onTap: () => unawaited(_editDefault(state, rules)),
          ),
        ],
      ),
      _ChainCard(state: state, rules: rules, onTap: _openChains),
      Row(
        spacing: WSpace.s,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => unawaited(_export(rules)),
              child: const Text('Exportieren'),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: () => unawaited(_import(state)),
              child: const Text('Importieren'),
            ),
          ),
        ],
      ),
    ];
  }

  void _open(Widget screen) => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );

  void _openChains() => _open(const ChainEditorScreen());

  Future<void> _editDefault(RoutingState state, RuleSet rules) async {
    final target = await pickTarget(
      context,
      title: 'Standardziel',
      profiles: state.profiles,
      initial: rules.defaultTarget,
    );
    if (target == null || target == rules.defaultTarget) return;
    await _notifier.save(rules.copyWith(defaultTarget: target));
  }

  Future<void> _export(RuleSet rules) => ref.read(exporterProvider)(
    'wendelin-routing.json',
    'application/json',
    const JsonEncoder.withIndent('  ').convert(RuleSetJson().encode(rules)),
  );

  Future<void> _import(RoutingState state) async {
    final String? text;
    try {
      text = await ref.read(routingImporterProvider)();
    } on PortException catch (e) {
      if (mounted) showHint(context, e.message);
      return;
    }
    if (text == null || !mounted) return;
    final RuleSet imported;
    try {
      imported = RuleSetJson().decode(jsonDecode(text));
    } on FormatException catch (e) {
      // Also RuleSetFormatException (German text with the JSON path).
      showHint(context, 'Import nicht möglich: ${e.message}');
      return;
    }
    final preview = ImportPreview(current: state, imported: imported);
    final ok = await showImportPreview(context, preview);
    if (ok && mounted) await _notifier.save(preview.result);
  }

  Future<void> _reset() async {
    final ok = await confirm(
      context,
      title: 'Regeln zurücksetzen?',
      message:
          'Die gespeicherten Regeln werden verworfen und aus den '
          'Provider-Einstellungen neu angelegt.',
      yes: 'Zurücksetzen',
    );
    if (ok) await _notifier.reset();
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.controller,
    required this.state,
    required this.decision,
  });

  final TextEditingController controller;
  final RoutingState state;
  final RouteDecision? decision;

  @override
  Widget build(BuildContext context) {
    final d = decision;
    return Container(
      padding: const EdgeInsets.all(WSpace.l),
      decoration: BoxDecoration(
        color: WColors.surface,
        borderRadius: BorderRadius.circular(WRadius.cardLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WSpace.m,
        children: [
          Text('Testsatz', style: WText.sectionLabel),
          TextField(
            controller: controller,
            style: WText.body,
            decoration: const InputDecoration(
              hintText: 'Welche Regel greift für diesen Satz?',
            ),
          ),
          if (d != null) _result(d),
        ],
      ),
    );
  }

  Widget _result(RouteDecision d) {
    final (badge, text) = explainLabel(state, d);
    final skipped = [
      for (final s in d.skipped)
        if (s.reason != SkipReason.noMatch)
          '„${s.rule.name}“ übersprungen: ${skipLabel(s.reason)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.s,
      children: [
        Row(
          spacing: WSpace.s10,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: WSpace.s,
                vertical: WSpace.xs,
              ),
              decoration: BoxDecoration(
                color: WColors.accent,
                borderRadius: BorderRadius.circular(WRadius.small),
              ),
              child: Text(
                badge,
                style: WText.mono.copyWith(color: WColors.onAccent),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: WText.detail.copyWith(color: WColors.text),
              ),
            ),
          ],
        ),
        for (final s in skipped) Text(s, style: WText.caption),
      ],
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({
    required this.state,
    required this.rules,
    required this.onTap,
  });

  final RoutingState state;
  final RuleSet rules;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owner = rules.defaultTarget;
    final chain = [owner, ...rules.chainOf(owner.profileId)];
    final others = rules.chains.keys.where((k) => k != owner.profileId).length;
    return Material(
      color: WColors.surface,
      borderRadius: BorderRadius.circular(WRadius.buttonLarge),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(WSpace.m14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WSpace.xs6,
            children: [
              Text('Eskalation bei Fehlschlag', style: WText.sectionLabel),
              Text(
                chain.length == 1
                    ? '${targetLabel(state, owner)} → keine Kette'
                    : chain.map((t) => targetLabel(state, t)).join(' → '),
                style: WText.mono.copyWith(color: WColors.text),
              ),
              if (others > 0)
                Text(
                  '+ Ketten für $others weitere${others == 1 ? 's' : ''} '
                  'Profil${others == 1 ? '' : 'e'}',
                  style: WText.caption,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
