import 'dart:async';

import 'package:test/test.dart';

import '../src/common/port_exception.dart';
import '../src/media/media_port.dart';

/// Creates the [MediaControlPort] under test.
typedef MediaControlPortFactory = FutureOr<MediaControlPort> Function();

/// Names of the checks in [mediaControlPortContractChecks].
abstract final class MediaControlPortChecks {
  /// Without access reading throws `permissionDenied`, never anything else.
  static const noAccess = 'ohne Zugriff: permissionDenied statt Absturz';

  /// With access `nowPlaying` is a snapshot or `null`, and `seekTo`
  /// throws a `PortException` or succeeds.
  static const withAccess = 'mit Zugriff: Snapshot oder null';

  /// An app that is not installed gives `notFound`.
  static const unknownApp = 'unbekannte App: notFound';
}

/// Reusable contract suite for every [MediaControlPort]; registers one test
/// per entry of [mediaControlPortContractChecks]. It sends no commands, so
/// it is safe against a real device.
void mediaControlPortContract(
  MediaControlPortFactory create, {
  String name = 'MediaControlPort',
}) {
  group('$name erfüllt den MediaControlPort-Vertrag', () {
    mediaControlPortContractChecks(create).forEach(test);
  });
}

/// The checks of [mediaControlPortContract] by name
/// ([MediaControlPortChecks]).
Map<String, Future<void> Function()> mediaControlPortContractChecks(
  MediaControlPortFactory create,
) {
  return {
    MediaControlPortChecks.noAccess: () async {
      final p = await create();
      if (await p.hasSessionAccess()) return;
      await expectLater(
        p.nowPlaying(),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.permissionDenied,
          ),
        ),
      );
    },
    MediaControlPortChecks.withAccess: () async {
      final p = await create();
      if (!await p.hasSessionAccess()) return;
      final s = await p.nowPlaying();
      if (s == null) {
        await expectLater(
          p.seekTo(Duration.zero),
          throwsA(isA<PortException>()),
        );
      } else {
        expect(s.packageName, isNotEmpty);
        expect(s.appName, isNotEmpty);
      }
    },
    MediaControlPortChecks.unknownApp: () async {
      final p = await create();
      await expectLater(
        p.openApp('de.example.gibtesnicht'),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.notFound,
          ),
        ),
      );
    },
  };
}
