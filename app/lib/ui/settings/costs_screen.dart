import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/money.dart';
import '../../di/profiles.dart';
import '../../di/providers.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Costs of one profile today and this month (micro-USD).
@immutable
final class ProfileCosts {
  /// Creates the row.
  const ProfileCosts({
    required this.profileId,
    required this.name,
    required this.today,
    required this.month,
    this.budget,
  });

  /// Profile id.
  final String profileId;

  /// Display name.
  final String name;

  /// Spent today.
  final int today;

  /// Spent this month.
  final int month;

  /// Monthly budget, if set.
  final int? budget;
}

/// Costs per profile from the usage records (local day and month).
final costsProvider = FutureProvider.autoDispose<List<ProfileCosts>>((
  ref,
) async {
  final usage = ref.watch(storageProvider).usage;
  final now = ref.watch(clockProvider).now();
  final profiles = await ref.watch(profilesProvider.future);
  final dayStart = DateTime(now.year, now.month, now.day);
  final monthStart = DateTime(now.year, now.month);
  Future<int> sum(String id, DateTime from, {required bool byDay}) async {
    final totals = byDay
        ? await usage.totalsByDay(profileId: id, from: from)
        : await usage.totalsByMonth(profileId: id, from: from);
    return totals.fold<int>(0, (s, t) => s + t.costMicros);
  }

  return [
    for (final p in profiles.profiles)
      ProfileCosts(
        profileId: p.id,
        name: p.name,
        today: await sum(p.id, dayStart, byDay: true),
        month: await sum(p.id, monthStart, byDay: false),
        budget: p.budgetMonthly,
      ),
  ];
});

/// Settings → Kosten: today and this month per provider.
class CostsScreen extends ConsumerWidget {
  /// Creates the screen.
  const CostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costs = ref.watch(costsProvider).value ?? const <ProfileCosts>[];
    return SettingsPage(
      title: 'Kosten',
      intro: 'Nach den Preisen im Modellkatalog, in US-Dollar.',
      children: [
        if (costs.isEmpty)
          Text('Noch keine Provider.', style: WText.intro)
        else
          SectionCard(
            children: [
              for (final c in costs)
                SettingsRow(
                  title: c.name,
                  detail: [
                    'heute ${formatUsd(c.today)}',
                    'Monat ${formatUsd(c.month)}',
                    if (c.budget != null) 'von ${formatUsd(c.budget!)}',
                  ].join(' · '),
                ),
            ],
          ),
      ],
    );
  }
}
