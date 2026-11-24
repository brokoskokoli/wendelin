import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/providers.dart';
import '../../di/weather.dart';
import '../../di/weather_config.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../voice/microphone_access.dart' show appSettingsOpenerProvider;
import 'settings_page.dart';

/// Settings → Wetter und Meer: choose the weather service, whether the GPS
/// position is used for questions without a place, and the home place
/// (looked up with the Open-Meteo geocoder).
class WeatherScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherState();
}

class _WeatherState extends ConsumerState<WeatherScreen> {
  late WeatherServiceKind _kind;
  late bool _useGps;
  final _home = TextEditingController();
  String? _error;
  bool _busy = false;

  /// The location permission is missing while [_useGps] is on.
  bool _gpsDenied = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(weatherConfigProvider);
    _kind = config.kind;
    _useGps = config.useGps;
    _home.text = config.home?.name ?? '';
    if (_useGps) unawaited(_checkPermission());
  }

  /// Shows the hint if the box is ticked but the permission went away.
  Future<void> _checkPermission() async {
    final port = ref.read(platformPortsProvider).location;
    if (port == null) return;
    final granted = await port.hasPermission();
    if (mounted && _useGps) setState(() => _gpsDenied = !granted);
  }

  /// Ticking asks for the location permission (foreground, explained
  /// first); unticking does not ask. A refusal keeps the box ticked and
  /// shows the hint; the weather then falls back to the home place.
  Future<void> _toggleGps(bool on) async {
    if (!on) {
      setState(() {
        _useGps = false;
        _gpsDenied = false;
      });
      return;
    }
    final port = ref.read(platformPortsProvider).location;
    if (port == null) {
      setState(() => _useGps = true);
      return;
    }
    if (!await port.hasPermission()) {
      if (!mounted) return;
      final ok = await confirm(
        context,
        title: context.l10n.integrationsPermission2,
        message: context.l10n.weatherGpsRationale,
        yes: context.l10n.next,
      );
      if (!ok || !mounted) return;
    }
    final granted = await port.requestPermission();
    if (!mounted) return;
    setState(() {
      _useGps = true;
      _gpsDenied = !granted;
    });
  }

  @override
  void dispose() {
    _home.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final old = ref.read(weatherConfigProvider);
    final text = _home.text.trim();
    Place? home;
    if (text.isNotEmpty) {
      if (old.home?.name == text) {
        home = old.home;
      } else {
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          home = await ref
              .read(weatherGeocoderProvider)
              .find(text, language: 'de');
        } on PortException {
          home = null;
          if (mounted) {
            setState(() => _error = context.l10n.weatherSearchFailed);
          }
        }
        if (!mounted) return;
        setState(() => _busy = false);
        if (home == null) {
          setState(() => _error ??= context.l10n.weatherNotFound(text));
          return;
        }
      }
    }
    await ref
        .read(weatherConfigProvider.notifier)
        .set(WeatherConfig(kind: _kind, home: home, useGps: _useGps));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: context.l10n.weatherTitle,
      intro: context.l10n.weatherIntro,
      children: [
        SectionCard(
          children: [
            for (final k in WeatherServiceKind.values)
              SettingsRow(
                title: k.label,
                detail: k.detailOf(context.l10n),
                onTap: () => setState(() => _kind = k),
                trailing: _kind == k
                    ? CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: context.l10n.selected,
                      )
                    : null,
              ),
          ],
        ),
        SectionCard(
          children: [
            SettingsRow(
              title: context.l10n.weatherUseGps,
              detail: context.l10n.weatherUseGpsHelp,
              onTap: () => unawaited(_toggleGps(!_useGps)),
              trailing: WSwitch(
                key: const ValueKey('weatherUseGps'),
                value: _useGps,
                semanticLabel: context.l10n.weatherUseGps,
                onChanged: (on) => unawaited(_toggleGps(on)),
              ),
            ),
          ],
        ),
        if (_useGps && _gpsDenied)
          StatusCard(
            key: const ValueKey('weatherGpsDenied'),
            status: CheckStatus.pending,
            title: context.l10n.weatherGpsDenied,
            detail: context.l10n.weatherGpsDeniedDetail,
            actionBelow: true,
            action: LinkButton(
              context.l10n.weatherGpsOpenSettings,
              onPressed: () => unawaited(ref.read(appSettingsOpenerProvider)()),
            ),
          ),
        TextField(
          key: const ValueKey('weatherHome'),
          controller: _home,
          style: WText.body,
          decoration: InputDecoration(labelText: context.l10n.weatherHomeLabel),
        ),
        InfoBox(context.l10n.weatherHomeHelp),
        if (_error != null) Text(_error!, style: WText.caption),
        PrimaryButton(
          context.l10n.save,
          onPressed: _busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}
