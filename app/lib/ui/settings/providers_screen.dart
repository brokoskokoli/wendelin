import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/money.dart';
import '../../di/profiles.dart';
import '../design/design.dart';
import '../routes.dart';
import 'provider_setup_screen.dart';
import 'settings_page.dart';

/// Settings → Provider: profiles with privacy chip, the default profile and
/// the escalation chain (order of escalation).
class ProvidersScreen extends ConsumerWidget {
  /// Creates the screen.
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profilesProvider);
    final notifier = ref.read(profilesProvider.notifier);
    final data = state.value;
    return SettingsPage(
      title: 'Provider',
      intro:
          'Der Standard bekommt jede Anfrage. Scheitert er, übergibt '
          'Wendelin an die Eskalationskette, der Reihe nach.',
      children: [
        if (data == null)
          Text(
            state.hasError ? 'Fehler: ${state.error}' : '…',
            style: WText.caption,
          )
        else ...[
          if (data.profiles.isEmpty)
            Text('Noch kein Provider eingerichtet.', style: WText.intro)
          else
            SettingsSection(
              title: 'Profile',
              children: [
                for (final p in data.profiles)
                  _ProfileRow(
                    profile: p,
                    isDefault: p.id == data.defaultId,
                    onDefault: () => unawaited(notifier.setDefault(p.id)),
                    onEdit: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProviderSetupScreen(existing: p),
                      ),
                    ),
                    onDelete: () => unawaited(_delete(context, notifier, p)),
                  ),
              ],
            ),
          if (data.profiles.length > 1) _ChainSection(data, notifier),
        ],
        WideButton(
          '+ Provider',
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.providerSetup),
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    ProfilesNotifier notifier,
    ProviderProfile p,
  ) async {
    final ok = await confirm(
      context,
      title: '„${p.name}“ löschen?',
      message: 'Profil und gespeicherter Key werden entfernt.',
      yes: 'Löschen',
    );
    if (ok) await notifier.delete(p.id);
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.isDefault,
    required this.onDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final ProviderProfile profile;
  final bool isDefault;
  final VoidCallback onDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final budget = profile.budgetMonthly;
    return Padding(
      padding: const EdgeInsets.all(WSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WSpace.s,
        children: [
          ProviderChip(name: profile.name, level: profile.privacy),
          Text(
            [
              profile.defaultModel,
              if (budget != null) 'Budget ${formatUsd(budget)}/Monat',
              if (isDefault) 'Standard',
            ].join(' · '),
            style: WText.mono,
          ),
          Wrap(
            spacing: WSpace.s,
            runSpacing: WSpace.s,
            children: [
              OutlinedButton(
                onPressed: onEdit,
                child: const Text('Bearbeiten'),
              ),
              if (!isDefault)
                OutlinedButton(
                  onPressed: onDefault,
                  child: const Text('Als Standard'),
                ),
              OutlinedButton(onPressed: onDelete, child: const Text('Löschen')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChainSection extends StatelessWidget {
  const _ChainSection(this.data, this.notifier);

  final ProfilesState data;
  final ProfilesNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final chain = data.chain;
    final candidates = [
      for (final p in data.profiles)
        if (p.id != data.defaultId) p,
    ];
    void set(List<String> ids) => unawaited(notifier.setChain(ids));
    return SettingsSection(
      title: 'Eskalationskette',
      children: [
        for (final p in candidates)
          SettingsRow(
            title: p.name,
            detail: chain.contains(p.id)
                ? 'Platz ${chain.indexOf(p.id) + 1}'
                : 'nicht in der Kette',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chain.indexOf(p.id) > 0)
                  TextButton(
                    onPressed: () {
                      final i = chain.indexOf(p.id);
                      set(
                        [...chain]
                          ..removeAt(i)
                          ..insert(i - 1, p.id),
                      );
                    },
                    child: Text(
                      'Früher',
                      semanticsLabel: '${p.name} früher in der Kette',
                    ),
                  ),
                WSwitch(
                  value: chain.contains(p.id),
                  semanticLabel: '${p.name} in der Eskalationskette',
                  onChanged: (on) => set(
                    on
                        ? [...chain, p.id]
                        : [
                            for (final c in chain)
                              if (c != p.id) c,
                          ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
