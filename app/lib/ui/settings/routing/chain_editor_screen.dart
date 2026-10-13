import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../../di/routing.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'routing_texts.dart';
import 'target_picker.dart';

/// Hint of a chain link below the privacy level of the chain's profile.
String belowLevelHint(PrivacyLevel owner) =>
    'unter ${owner.label}: bei privaten Anfragen fragt Wendelin vorher nach';

/// Routing → Eskalationsketten: one chain per profile (ADR 0009 §4). Pick
/// the profile, sort its chain by dragging, add and remove links. Every
/// link shows its privacy level; links below the profile's level are
/// marked (the agent asks before handing a private request to them).
class ChainEditorScreen extends ConsumerStatefulWidget {
  /// Opens the chain of [profileId] (default: the default profile).
  const ChainEditorScreen({super.key, this.profileId});

  /// Profile whose chain is shown first.
  final String? profileId;

  @override
  ConsumerState<ChainEditorScreen> createState() => _ChainEditorScreenState();
}

class _ChainEditorScreenState extends ConsumerState<ChainEditorScreen> {
  String? _owner;

  Future<void> _set(RoutingState state, List<RouteTarget> chain) {
    final rules = state.rules!;
    final owner = _owner!;
    return ref
        .read(routingProvider.notifier)
        .save(
          rules.copyWith(
            chains: {
              for (final e in rules.chains.entries)
                if (e.key != owner) e.key: e.value,
              if (chain.isNotEmpty) owner: chain,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(routingProvider).value;
    final rules = state?.rules;
    if (state == null || rules == null) {
      return const SettingsPage(title: 'Eskalationsketten', children: []);
    }
    final owner = _owner ??= widget.profileId ?? rules.defaultTarget.profileId;
    final ownerLevel = state.profile(owner)?.privacy;
    final chain = rules.chainOf(owner);
    return SettingsPage(
      title: 'Eskalationsketten',
      intro:
          'Scheitert ein Provider, übergibt Wendelin an das nächste Glied '
          'der Kette des Profils, über das die Anfrage geroutet wurde.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: state.profile(owner) == null ? null : owner,
          isExpanded: true,
          dropdownColor: WColors.surfaceRaised,
          decoration: const InputDecoration(labelText: 'Kette von'),
          items: [
            for (final p in state.profiles)
              DropdownMenuItem(
                value: p.id,
                child: Text('${p.name} · ${p.privacy.label}'),
              ),
          ],
          onChanged: (id) => setState(() => _owner = id),
        ),
        if (chain.isEmpty)
          Text(
            'Keine Kette: Scheitert ${state.nameOf(owner)}, endet die '
            'Anfrage mit einem Fehler.',
            style: WText.intro,
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final list = [...chain];
              list.insert(to, list.removeAt(from));
              unawaited(_set(state, list));
            },
            children: [
              for (final (i, link) in chain.indexed)
                Padding(
                  key: ValueKey('$owner-$i-$link'),
                  padding: const EdgeInsets.only(bottom: WSpace.s),
                  child: _ChainLink(
                    index: i,
                    label: fullTargetLabel(state, link),
                    level: targetLevel(state, link),
                    ownerLevel: ownerLevel,
                    onRemove: () =>
                        unawaited(_set(state, [...chain]..removeAt(i))),
                  ),
                ),
            ],
          ),
        WideButton(
          '+ Glied',
          onPressed: () async {
            final others = [
              for (final p in state.profiles)
                if (p.id != owner) p,
            ];
            if (others.isEmpty) {
              showHint(context, 'Lege zuerst ein weiteres Profil an.');
              return;
            }
            final target = await pickTarget(
              context,
              title: 'Glied hinzufügen',
              profiles: others,
              initial: RouteTarget(
                profileId: others.first.id,
                modelId: others.first.defaultModel,
              ),
            );
            if (target != null) await _set(state, [...chain, target]);
          },
        ),
      ],
    );
  }
}

class _ChainLink extends StatelessWidget {
  const _ChainLink({
    required this.index,
    required this.label,
    required this.level,
    required this.ownerLevel,
    required this.onRemove,
  });

  final int index;
  final String label;
  final PrivacyLevel? level;
  final PrivacyLevel? ownerLevel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = level;
    final owner = ownerLevel;
    final below = l != null && owner != null && !l.isAtLeast(owner);
    return Material(
      color: WColors.surface,
      borderRadius: BorderRadius.circular(WRadius.buttonLarge),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Glied ${index + 1} verschieben',
              child: const SizedBox(
                width: WSize.touchMin,
                height: WSize.touchMin,
                child: Center(
                  child: WIcon(
                    WIcons.dragHandle,
                    size: WSize.ruleHandleWidth,
                    height: WSize.icon,
                    color: WColors.lineSubtle,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.xs,
                children: [
                  Text('${index + 1}. $label', style: WText.label),
                  if (l == null)
                    Text(
                      'Profil gelöscht, wird übersprungen',
                      style: WText.detail.copyWith(color: WColors.warn),
                    )
                  else
                    PrivacyChip(l),
                  if (below)
                    Text(
                      belowLevelHint(owner),
                      style: WText.detail.copyWith(color: WColors.warn),
                    ),
                ],
              ),
            ),
          ),
          WIconButton(
            icon: WIcons.close,
            tooltip: 'Glied ${index + 1} entfernen',
            shape: WIconButtonShape.round,
            iconSize: WSize.iconSmall,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
