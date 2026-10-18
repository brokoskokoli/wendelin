/// German description of a WMO weather code (Open-Meteo).
String wmoCondition(int? code) => switch (code) {
  0 => 'klar',
  1 => 'überwiegend klar',
  2 => 'teils bewölkt',
  3 => 'bedeckt',
  45 || 48 => 'Nebel',
  51 => 'leichter Nieselregen',
  53 => 'Nieselregen',
  55 => 'starker Nieselregen',
  56 || 57 => 'gefrierender Nieselregen',
  61 => 'leichter Regen',
  63 => 'Regen',
  65 => 'starker Regen',
  66 || 67 => 'gefrierender Regen',
  71 => 'leichter Schneefall',
  73 => 'Schneefall',
  75 => 'starker Schneefall',
  77 => 'Schneegriesel',
  80 => 'leichte Regenschauer',
  81 => 'Regenschauer',
  82 => 'heftige Regenschauer',
  85 || 86 => 'Schneeschauer',
  95 => 'Gewitter',
  96 || 99 => 'Gewitter mit Hagel',
  _ => 'unbekannt',
};

/// German description of a Bright Sky icon (or condition) name.
String brightSkyCondition(String? icon) => switch (icon) {
  'clear-day' || 'clear-night' => 'klar',
  'partly-cloudy-day' || 'partly-cloudy-night' => 'teils bewölkt',
  'cloudy' => 'bedeckt',
  'fog' => 'Nebel',
  'wind' => 'windig',
  'rain' => 'Regen',
  'sleet' => 'Schneeregen',
  'snow' => 'Schnee',
  'hail' => 'Hagel',
  'thunderstorm' => 'Gewitter',
  'dry' => 'trocken',
  _ => 'unbekannt',
};

/// German description of a MET Norway `symbol_code`
/// (`lightrainshowersandthunder_day`, `partlycloudy_night`, …).
String metSymbolCondition(String? symbol) {
  if (symbol == null) return 'unbekannt';
  final code = symbol.replaceFirst(RegExp(r'_(day|night|polartwilight)$'), '');
  final thunder = code.contains('andthunder');
  final base = code.replaceAll('andthunder', '');
  final strength = base.startsWith('light')
      ? 'leicht'
      : base.startsWith('heavy')
      ? 'stark'
      : '';
  final kind = base.replaceFirst(RegExp('^(light|heavy)'), '');
  final text = switch (kind) {
    'clearsky' => 'klar',
    'fair' => 'überwiegend klar',
    'partlycloudy' => 'teils bewölkt',
    'cloudy' => 'bedeckt',
    'fog' => 'Nebel',
    'rain' => _graded(strength, 'Regen', 'er Regen'),
    'rainshowers' => _graded(strength, 'Regenschauer', 'e Regenschauer'),
    'sleet' => _graded(strength, 'Schneeregen', 'er Schneeregen'),
    'sleetshowers' => _graded(
      strength,
      'Schneeregenschauer',
      'e Schneeregenschauer',
    ),
    'snow' => _graded(strength, 'Schnee', 'er Schnee'),
    'snowshowers' => _graded(strength, 'Schneeschauer', 'e Schneeschauer'),
    _ => thunder ? '' : 'unbekannt',
  };
  if (!thunder) return text;
  return text.isEmpty ? 'Gewitter' : '$text mit Gewitter';
}

String _graded(String strength, String plain, String suffix) =>
    switch (strength) {
      'leicht' => 'leicht$suffix',
      'stark' => 'stark$suffix',
      _ => plain,
    };
