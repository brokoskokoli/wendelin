import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../ui/theme/app_theme.dart';
import '../station_data.dart';
import '../station_drift.dart';
import '../station_prefs.dart';
import '../station_providers.dart';

/// Size of the clock.
const _clockSize = 112.0;

/// The idle display of the station mode (WP99): clock, date, weather, next
/// appointments and due tasks with titles, slots for playback and tiles
/// (WP100). Every area can be switched off; a switched-off area is not read
/// at all. A touch wakes the screen; „Beenden“ asks to unlock first.
class StationScreen extends ConsumerWidget {
  /// Creates the screen.
  const StationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(stationLookProvider);
    final prefs = ref.watch(stationPrefsProvider);
    final state = ref.watch(stationControllerProvider);
    final info = ref.watch(stationInfoProvider).value ?? const StationInfo();
    final palette = _Palette.of(look);
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale).format(state.now);
    final date = DateFormat.MMMMEEEEd(locale).format(state.now);
    final quiet = look == StationLook.quiet;
    return Listener(
      onPointerDown: (_) =>
          ref.read(stationControllerProvider.notifier).touch(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WSpace.screen),
            child: Transform.translate(
              offset: stationDrift(state.now),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    key: const ValueKey('stationClock'),
                    style: TextStyle(
                      fontFamily: WFonts.ui,
                      fontSize: _clockSize,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                      height: 1,
                    ),
                  ),
                  Text(
                    date,
                    key: const ValueKey('stationDate'),
                    style: WText.cardTitle.copyWith(color: palette.secondary),
                  ),
                  if (!quiet)
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(top: WSpace.xxl),
                        children: [
                          if (prefs.shows(StationSection.weather) &&
                              info.weather != null)
                            _Weather(info.weather!, palette),
                          if (prefs.shows(StationSection.events))
                            _Events(info.events, palette),
                          if (prefs.shows(StationSection.tasks))
                            _Tasks(info.tasks, palette),
                          if (prefs.shows(StationSection.playback))
                            _Slot(
                              context.l10n.stationPlaybackSlot,
                              palette,
                              key: const ValueKey('stationPlaybackSlot'),
                            ),
                          if (prefs.shows(StationSection.tiles))
                            _Slot(
                              context.l10n.stationTilesSlot,
                              palette,
                              key: const ValueKey('stationTilesSlot'),
                            ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('stationEnd'),
                      onPressed: state.ending
                          ? null
                          : () => unawaited(
                              ref
                                  .read(stationControllerProvider.notifier)
                                  .end(),
                            ),
                      child: Text(
                        context.l10n.stationEnd,
                        style: WText.button.copyWith(color: palette.secondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _Palette {
  const _Palette(this.primary, this.secondary);

  factory _Palette.of(StationLook look) => switch (look) {
    StationLook.normal => const _Palette(WColors.text, WColors.textSecondary),
    StationLook.dim => const _Palette(WColors.textMuted, WColors.lineSubtle),
    StationLook.quiet => const _Palette(WColors.line, WColors.line),
  };

  final Color primary;
  final Color secondary;
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, this.palette);

  final String text;
  final _Palette palette;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WSpace.l, bottom: WSpace.s),
    child: Text(
      text.toUpperCase(),
      style: WText.sectionLabel.copyWith(color: palette.secondary),
    ),
  );
}

class _Weather extends StatelessWidget {
  const _Weather(this.weather, this.palette);

  final StationWeather weather;
  final _Palette palette;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('stationWeather'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Heading(context.l10n.stationWeather, palette),
      Text(
        '${weather.temperatureC.round()} °C · ${weather.condition}',
        style: WText.transcript.copyWith(color: palette.primary),
      ),
      Text(
        weather.place,
        style: WText.detail.copyWith(color: palette.secondary),
      ),
    ],
  );
}

class _Events extends StatelessWidget {
  const _Events(this.events, this.palette);

  final List<StationEvent> events;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    return Column(
      key: const ValueKey('stationEvents'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l.stationEvents, palette),
        if (events.isEmpty)
          Text(
            l.stationNoEvents,
            style: WText.body.copyWith(color: palette.secondary),
          )
        else
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: WSpace.s),
              child: Text(
                '${e.allDay ? l.stationAllDay : DateFormat.Hm(locale).format(e.start)}  ${e.title}',
                style: WText.itemTitle.copyWith(color: palette.primary),
              ),
            ),
      ],
    );
  }
}

class _Tasks extends StatelessWidget {
  const _Tasks(this.tasks, this.palette);

  final List<StationTask> tasks;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      key: const ValueKey('stationTasks'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l.stationTasks, palette),
        if (tasks.isEmpty)
          Text(
            l.stationNoTasks,
            style: WText.body.copyWith(color: palette.secondary),
          )
        else
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: WSpace.s),
              child: Text(
                t.overdue ? '${t.title} · ${l.stationOverdue}' : t.title,
                style: WText.itemTitle.copyWith(color: palette.primary),
              ),
            ),
      ],
    );
  }
}

/// Placeholder of an area WP100 fills (playback, tiles).
class _Slot extends StatelessWidget {
  const _Slot(this.label, this.palette, {super.key});

  final String label;
  final _Palette palette;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Heading(label, palette),
      Text(
        context.l10n.stationSlotSoon,
        style: WText.detail.copyWith(color: palette.secondary),
      ),
    ],
  );
}
