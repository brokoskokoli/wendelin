/// German display of an amount in micro-USD, e.g. `30000` → „0,03 $“.
///
/// Costs are kept in USD (model prices); there is no currency conversion.
String formatUsd(int micros) {
  final cents = (micros / 10000).round();
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final dollars = abs ~/ 100;
  final rest = (abs % 100).toString().padLeft(2, '0');
  return '$sign$dollars,$rest \$';
}
