import 'dart:async';

import 'package:test/test.dart';

import '../src/common/app_presence.dart';

/// Creates the [AppPresencePort] under test for a device on which exactly
/// the packages in `installed` are installed (and declared visible).
typedef AppPresencePortFactory = FutureOr<AppPresencePort> Function(
  Set<String> installed,
);

/// Names of the checks in [appPresencePortContractChecks].
abstract final class AppPresencePortChecks {
  /// An installed package is reported as installed.
  static const installed = 'installiertes Paket: true';

  /// A missing package is reported as missing.
  static const missing = 'fehlendes Paket: false';

  /// Package names are compared exactly (case, prefixes).
  static const exact = 'Paketname wird genau verglichen (Groß/klein, Präfix)';

  /// Invalid package names throw ArgumentError.
  static const invalid = 'ungültiger Paketname wirft ArgumentError';

  /// Concurrent queries get their own answers.
  static const concurrent = 'parallele Abfragen bekommen je ihre Antwort';
}

/// Reusable contract suite for every [AppPresencePort] implementation;
/// registers one test per entry of [appPresencePortContractChecks].
void appPresencePortContract(
  AppPresencePortFactory create, {
  String name = 'AppPresencePort',
}) {
  group('$name erfüllt den AppPresencePort-Vertrag', () {
    appPresencePortContractChecks(create).forEach(test);
  });
}

/// The checks of [appPresencePortContract] by name ([AppPresencePortChecks]).
Map<String, Future<void> Function()> appPresencePortContractChecks(
  AppPresencePortFactory create,
) {
  const obsidian = 'md.obsidian';
  const bring = 'ch.publisheria.bring';
  const spotify = 'com.spotify.music';
  return {
    AppPresencePortChecks.installed: () async {
      final port = await create({obsidian, bring});
      expect(await port.isInstalled(obsidian), isTrue);
      expect(await port.isInstalled(bring), isTrue);
    },
    AppPresencePortChecks.missing: () async {
      final port = await create({obsidian});
      expect(await port.isInstalled(spotify), isFalse);
      // Repeated queries stay stable.
      expect(await port.isInstalled(spotify), isFalse);
      expect(await port.isInstalled(obsidian), isTrue);
    },
    AppPresencePortChecks.exact: () async {
      final port = await create({obsidian});
      expect(await port.isInstalled('MD.OBSIDIAN'), isFalse);
      expect(await port.isInstalled('md.obsidian.beta'), isFalse);
      expect(await port.isInstalled('md.obsidia'), isFalse);
    },
    AppPresencePortChecks.invalid: () async {
      final port = await create({obsidian});
      for (final name in [
        '',
        'obsidian',
        'md..obsidian',
        'md.obsidian ',
        '1.a',
      ]) {
        await expectLater(
          port.isInstalled(name),
          throwsA(isA<ArgumentError>()),
          reason: '„$name“',
        );
      }
    },
    AppPresencePortChecks.concurrent: () async {
      final port = await create({obsidian, spotify});
      final results = await Future.wait([
        port.isInstalled(obsidian),
        port.isInstalled(bring),
        port.isInstalled(spotify),
      ]);
      expect(results, [true, false, true]);
    },
  };
}
