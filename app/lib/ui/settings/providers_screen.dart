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
import 'switch_topic.dart';

/// Settings → Provider: profiles with privacy chip and the default
/// profile.
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
          'Der Standard bekommt jede Anfrage, für die keine Routing-Regel '
          'greift. Scheitert er, sagt Wendelin das klar und wechselt nie von '
          'selbst zu einem anderen Anbieter.',
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
                    onDefault: () => unawaited(
                      _makeDefault(
                        context,
                        ref,
                        notifier,
                        p.id,
                        data.defaultId,
                      ),
                    ),
                    onEdit: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProviderSetupScreen(existing: p),
                      ),
                    ),
                    onDelete: () => unawaited(_delete(context, notifier, p)),
                  ),
              ],
            ),
          if (data.profiles.length > 1)
            SettingsSection(
              title: 'Anbieterwahl',
              children: [
                SettingsRow(
                  title: 'Routing',
                  detail: 'Regeln für die Wahl des Anbieters',
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.routing),
                ),
              ],
            ),
        ],
        WideButton(
          '+ Provider',
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.providerSetup),
        ),
      ],
    );
  }

  /// Manual change of the default: starts a new conversation (WP78).
  Future<void> _makeDefault(
    BuildContext context,
    WidgetRef ref,
    ProfilesNotifier notifier,
    String id,
    String? currentDefault,
  ) async {
    if (id != currentDefault && !await confirmManualModelSwitch(context, ref)) {
      return;
    }
    await notifier.setDefault(id);
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
