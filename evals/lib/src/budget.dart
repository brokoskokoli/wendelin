/// Cost limit of an eval run (`--max-cost`), in micro-USD.
///
/// Fail-closed: the limit counts as reached at `spent >= limit`, and a model
/// call without a known price also stops the run (the spent sum would no
/// longer be reliable).
final class CostBudget {
  /// Creates a budget of [usd] dollars; throws [ArgumentError] unless
  /// positive.
  CostBudget(double usd) : limitMicros = _micros(usd);

  static int _micros(double usd) {
    if (!usd.isFinite || !(usd > 0) || (usd * 1e6).round() < 1) {
      throw ArgumentError.value(usd, 'usd', 'muss > 0 sein');
    }
    return (usd * 1e6).round();
  }

  /// Limit in micro-USD.
  final int limitMicros;

  int _spent = 0;
  String? _stopReason;

  /// Summed cost of all recorded model calls in micro-USD.
  int get spentMicros => _spent;

  /// Why the run must stop; `null` while it may go on.
  String? get stopReason => _stopReason;

  /// Whether the run must stop.
  bool get exceeded => _stopReason != null;

  /// Records one model call ([micros] = `null`: price unknown); returns
  /// whether the run may go on.
  bool record(int? micros) {
    if (micros == null) {
      _stopReason ??= 'Kosten eines Modellaufrufs unbekannt (kein Preis)';
      return false;
    }
    _spent += micros;
    if (_spent >= limitMicros) {
      _stopReason ??= 'Kostengrenze erreicht ($_spent von $limitMicros µUSD)';
    }
    return !exceeded;
  }
}
