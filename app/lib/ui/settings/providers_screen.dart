import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/money.dart';
import '../../di/profiles.dart';
import '../../l10n/l10n.dart';
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
      title: context.l10n.areaProvider,
      intro: context.l10n.providersIntro,
      children: [
        if (data == null)
          Text(
            state.hasError
                ? context.l10n.providersError('${state.error}')
                : '…',
            style: WText.caption,
          )
        else ...[
          if (data.profiles.isEmpty)
            Text(context.l10n.providersNone, style: WText.intro)
          else
            SettingsSection(
              title: context.l10n.providersProfiles,
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
              title: context.l10n.providersChoice,
              children: [
                SettingsRow(
                  title: context.l10n.areaRouting,
                  detail: context.l10n.providersRoutingHint,
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.routing),
                ),
              ],
            ),
        ],
        WideButton(
          context.l10n.providersAdd,
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
      title: context.l10n.providersDeleteTitle(p.name),
      message: context.l10n.providersDeleteBody,
      yes: context.l10n.delete,
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
              if (budget != null)
                context.l10n.providersBudget(
                  formatUsdFor(context.l10n, budget),
                ),
              if (isDefault) context.l10n.routingDefault,
            ].join(' · '),
            style: WText.mono,
          ),
          Wrap(
            spacing: WSpace.s,
            runSpacing: WSpace.s,
            children: [
              OutlinedButton(onPressed: onEdit, child: Text(context.l10n.edit)),
              if (!isDefault)
                OutlinedButton(
                  onPressed: onDefault,
                  child: Text(context.l10n.providersMakeDefault),
                ),
              OutlinedButton(
                onPressed: onDelete,
                child: Text(context.l10n.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
