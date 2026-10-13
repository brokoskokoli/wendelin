/// Whether another app is installed on the device (concept: „App-Erkennung“).
///
/// Android: the package must be declared in `<queries>` of the app
/// manifest, otherwise Android 11+ hides it and the answer is always
/// `false`. Implementations check [androidPackage] with
/// [isValidAndroidPackage] and throw [ArgumentError] for invalid names; a
/// failed query throws a `PortException`. Must pass `appPresencePortContract`.
abstract interface class AppPresencePort {
  /// Whether the app with the package name [androidPackage] (e.g.
  /// `md.obsidian`) is installed. Package names are case-sensitive.
  Future<bool> isInstalled(String androidPackage);
}

final _packagePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
);

/// Whether [name] is a syntactically valid Android package name (at least
/// two segments of letters, digits and `_`, each starting with a letter).
bool isValidAndroidPackage(String name) => _packagePattern.hasMatch(name);

/// Throws [ArgumentError] unless [name] is a valid Android package name.
void checkAndroidPackage(String name) {
  if (!isValidAndroidPackage(name)) {
    throw ArgumentError.value(name, 'androidPackage', 'ungültiger Paketname');
  }
}
