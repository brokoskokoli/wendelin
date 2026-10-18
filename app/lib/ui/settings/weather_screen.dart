import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/weather.dart';
import '../../di/weather_config.dart';
import '../design/design.dart';
import 'settings_page.dart';
import 'weather_texts.dart';

/// Settings → Wetter und Meer: choose the weather service and the home
/// place (looked up with the Open-Meteo geocoder).
class WeatherScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherState();
}

class _WeatherState extends ConsumerState<WeatherScreen> {
  late WeatherServiceKind _kind;
  final _home = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(weatherConfigProvider);
    _kind = config.kind;
    _home.text = config.home?.name ?? '';
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
          if (mounted) setState(() => _error = WeatherTexts.searchFailed);
        }
        if (!mounted) return;
        setState(() => _busy = false);
        if (home == null) {
          setState(() => _error ??= WeatherTexts.notFound(text));
          return;
        }
      }
    }
    await ref
        .read(weatherConfigProvider.notifier)
        .set(WeatherConfig(kind: _kind, home: home));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: WeatherTexts.title,
      intro: WeatherTexts.intro,
      children: [
        SectionCard(
          children: [
            for (final k in WeatherServiceKind.values)
              SettingsRow(
                title: k.label,
                detail: k.detail,
                onTap: () => setState(() => _kind = k),
                trailing: _kind == k
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: WeatherTexts.selected,
                      )
                    : null,
              ),
          ],
        ),
        TextField(
          key: const ValueKey('weatherHome'),
          controller: _home,
          style: WText.body,
          decoration: const InputDecoration(labelText: WeatherTexts.homeLabel),
        ),
        Text(WeatherTexts.homeHelp, style: WText.caption),
        if (_error != null) Text(_error!, style: WText.caption),
        PrimaryButton(
          WeatherTexts.save,
          onPressed: _busy ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}
