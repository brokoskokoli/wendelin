/// Data-protection level of a provider, ordered
/// `local > tee > eu > standard`.
enum PrivacyLevel {
  /// Runs on the device or a self-hosted server.
  local(3),

  /// Runs inside an attested trusted execution environment.
  tee(2),

  /// Processed within the EU.
  eu(1),

  /// Ordinary cloud provider.
  standard(0);

  const PrivacyLevel(this._rank);

  final int _rank;

  /// Whether this level offers at least the protection of [other]
  /// (e.g. `tee.isAtLeast(eu)` is true, `eu.isAtLeast(tee)` is false).
  bool isAtLeast(PrivacyLevel other) => _rank >= other._rank;
}
