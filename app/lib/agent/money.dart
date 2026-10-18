import '../l10n/l10n.dart';

/// German display of an amount in micro-USD, e.g. `30000` → „0,03 $“; with
/// [english] `$0.03`.
///
/// Costs are kept in USD (model prices); there is no currency conversion.
String formatUsd(int micros, {bool english = false}) {
  final cents = (micros / 10000).round();
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final dollars = abs ~/ 100;
  final rest = (abs % 100).toString().padLeft(2, '0');
  return english ? '$sign\$$dollars.$rest' : '$sign$dollars,$rest \$';
}

/// [formatUsd] in the number format of the app language [l] (English with
/// decimal point, German and French with comma).
String formatUsdFor(AppLocalizations l, int micros) =>
    formatUsd(micros, english: l.localeName == 'en');
