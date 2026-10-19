import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Another app an integration uses (concept: „App-Erkennung“).
///
/// Without a [needed] app the integration is „nicht verfügbar“ (greyed
/// out, link to [storeUrl]); an optional app only adds [missingHint] to the
/// integration's line. The package must be declared in `<queries>` of the
/// Android manifest (see [KnownApps]).
final class AppRequirement {
  /// Creates a requirement.
  const AppRequirement({
    required this.androidPackage,
    required this.appName,
    required this.storeUrl,
    this.needed = true,
    this.missingHint,
  });

  /// Android package name, e.g. `md.obsidian`.
  final String androidPackage;

  /// Name of the app for the UI.
  final String appName;

  /// Where to get the app: F-Droid or the maker's page, no Play Store
  /// requirement (K7).
  final String storeUrl;

  /// Whether the integration only works with the app.
  final bool needed;

  /// Hint shown while an optional app is missing.
  final String? missingHint;

  /// The same app as an optional requirement with [hint].
  AppRequirement optional(String hint) => AppRequirement(
    androidPackage: androidPackage,
    appName: appName,
    storeUrl: storeUrl,
    needed: false,
    missingHint: hint,
  );
}

/// Apps the integrations know. Every package here is declared in
/// `<queries>` of `android/app/src/main/AndroidManifest.xml` (checked by a
/// test); Android 11+ hides all others.
abstract final class KnownApps {
  /// Bring! shopping list (WP24/WP28: optional fallback).
  static const bring = AppRequirement(
    androidPackage: 'ch.publisheria.bring',
    appName: 'Bring!',
    storeUrl: 'https://www.getbring.com/',
  );

  /// Obsidian (opens notes and daily notes; the vault itself is a folder).
  static const obsidian = AppRequirement(
    androidPackage: 'md.obsidian',
    appName: 'Obsidian',
    storeUrl: 'https://obsidian.md/download',
  );

  /// Spotify (WP84: optional, wakes the phone's own player).
  static const spotify = AppRequirement(
    androidPackage: 'com.spotify.music',
    appName: 'Spotify',
    storeUrl: 'https://www.spotify.com/download/',
  );

  /// Audible (`media__open_audible`; the other media tools work with any
  /// player).
  static const audible = AppRequirement(
    androidPackage: 'com.audible.application',
    appName: 'Audible',
    storeUrl: 'https://www.audible.de/',
    needed: false,
  );

  /// All known apps.
  static const all = [bring, obsidian, spotify, audible];
}

/// Last known answers of the [AppPresencePort]; filled by every check.
final class InstalledApps {
  /// Creates the cache over [port].
  InstalledApps(this.port);

  /// The device query.
  final AppPresencePort port;

  final Map<String, bool> _known = {};

  /// Whether [androidPackage] was installed at the last check; `null` if
  /// not checked yet or the check failed.
  bool? operator [](String androidPackage) => _known[androidPackage];

  /// Asks the device whether [androidPackage] is installed and remembers
  /// the answer. A failed query forgets the old answer and rethrows.
  Future<bool> check(String androidPackage) async {
    try {
      return _known[androidPackage] = await port.isInstalled(androidPackage);
    } on Object {
      _known.remove(androidPackage);
      rethrow;
    }
  }
}

/// Reason shown for an integration whose needed app is missing.
const appMissingReason = 'App nicht installiert';

/// An integration that checks its [requirement] before its own
/// availability. On every registry refresh (start, return to the app) the
/// app is checked again: if a needed app disappeared the integration turns
/// „nicht verfügbar“ and is paused, while its switch stays as it is.
final class AppRequirementGuard extends IntegrationDecorator {
  /// Wraps [inner].
  AppRequirementGuard(super.inner, this.requirement, this.apps);

  /// The app the integration uses.
  final AppRequirement requirement;

  /// Device query with cache (the UI reads hints from it).
  final InstalledApps apps;

  @override
  Future<Availability> checkAvailability() async {
    if (requirement.needed) {
      // A failed query propagates: the registry shows „Prüfung
      // fehlgeschlagen“ and pauses the tools.
      if (!await apps.check(requirement.androidPackage)) {
        return Availability(
          available: false,
          reason: appMissingReason,
          storeUrl: requirement.storeUrl,
        );
      }
    } else {
      try {
        await apps.check(requirement.androidPackage);
      } on PortException {
        // Optional app: unknown just means no hint (the cache has no
        // answer); the integration itself works.
      }
    }
    return inner.checkAvailability();
  }
}
