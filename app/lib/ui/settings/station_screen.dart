import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../station/station_prefs.dart';
import '../../station/station_providers.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Settings → Stationsmodus: screen behaviour, quiet hours and the areas the
/// station shows (WP99).
class StationSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const StationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final prefs = ref.watch(stationPrefsProvider);
    final notifier = ref.read(stationPrefsProvider.notifier);
    void save(StationPrefs p) => unawaited(notifier.set(p));
    return SettingsPage(
      title: l.stationTitle,
      intro: l.stationSettingsIntro,
      children: [
        SettingsSection(
          title: l.stationScreenSection,
          children: [
            for (final m in StationScreenMode.values)
              SettingsRow(
                title: _modeTitle(l, m),
                detail: _modeDetail(l, m),
                onTap: () => save(prefs.copyWith(screenMode: m)),
                trailing: prefs.screenMode == m
                    ? CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected)
                    : null,
              ),
          ],
        ),
        SettingsSection(
          title: l.stationQuietSection,
          children: [
            _HourRow(
              key: const ValueKey('quietFrom'),
              title: l.stationQuietFrom,
              hour: prefs.quiet.fromHour,
              onChanged: (h) => save(
                prefs.copyWith(
                  quiet: QuietHours(fromHour: h, toHour: prefs.quiet.toHour),
                ),
              ),
            ),
            _HourRow(
              key: const ValueKey('quietTo'),
              title: l.stationQuietTo,
              hour: prefs.quiet.toHour,
              onChanged: (h) => save(
                prefs.copyWith(
                  quiet: QuietHours(fromHour: prefs.quiet.fromHour, toHour: h),
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.stationSectionsSection,
          children: [
            Text(l.stationSectionsIntro, style: WText.intro),
            for (final s in StationSection.values)
              SettingsRow(
                title: _sectionTitle(l, s),
                trailing: WSwitch(
                  key: ValueKey('section-${s.name}'),
                  value: prefs.shows(s),
                  semanticLabel: _sectionTitle(l, s),
                  onChanged: (on) => save(
                    prefs.copyWith(
                      hidden: {
                        for (final h in prefs.hidden)
                          if (h != s) h,
                        if (!on) s,
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _modeTitle(AppLocalizations l, StationScreenMode m) => switch (m) {
  StationScreenMode.alwaysDimmed => l.stationScreenAlways,
  StationScreenMode.touchOnly => l.stationScreenTouch,
  StationScreenMode.daytimeOnly => l.stationScreenDaytime,
};

String _modeDetail(AppLocalizations l, StationScreenMode m) => switch (m) {
  StationScreenMode.alwaysDimmed => l.stationScreenAlwaysDetail,
  StationScreenMode.touchOnly => l.stationScreenTouchDetail,
  StationScreenMode.daytimeOnly => l.stationScreenDaytimeDetail,
};

String _sectionTitle(AppLocalizations l, StationSection s) => switch (s) {
  StationSection.weather => l.stationWeather,
  StationSection.events => l.stationEvents,
  StationSection.tasks => l.stationTasks,
  StationSection.playback => l.stationPlaybackSlot,
  StationSection.tiles => l.stationTilesSlot,
};

class _HourRow extends StatelessWidget {
  const _HourRow({
    super.key,
    required this.title,
    required this.hour,
    required this.onChanged,
  });

  final String title;
  final int hour;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title: title,
    trailing: DropdownButton<int>(
      value: hour,
      underline: const SizedBox.shrink(),
      style: WText.body,
      items: [
        for (var h = 0; h < 24; h++)
          DropdownMenuItem(value: h, child: Text(context.l10n.stationHour(h))),
      ],
      onChanged: (h) {
        if (h != null) onChanged(h);
      },
    ),
  );
}
