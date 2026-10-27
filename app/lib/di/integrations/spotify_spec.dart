import 'package:wendelin_integrations/common.dart'
    show PortErrorKind, ReconnectFailure;
import 'package:wendelin_integrations/spotify.dart';

import '../../voice/dev_log.dart';
import '../app_requirements.dart';
import '../core_providers.dart';
import '../spotify.dart';
import 'integration_spec.dart';

typedef _SpotifyDeps = ({
  SpotifyApi api,
  SpotifySecrets secrets,
  SpotifyAppLauncher launcher,
  SpotifyHostDevice hostDevice,
  SpotifyDelay? delay,
});

/// Spotify playback over the Web API.
final spotifySpec = IntegrationSpec(
  id: 'spotify',
  // A real account: not in the demo mode.
  prepare: (ref) => ref.watch(demoModeProvider)
      ? null
      : (
          api: ref.watch(spotifyApiProvider),
          secrets: ref.watch(spotifySecretsProvider),
          launcher: ref.watch(spotifyLauncherProvider),
          hostDevice: ref.watch(spotifyHostDeviceProvider),
          delay: ref.watch(spotifyDelayProvider),
        ),
  isSupported: (d) => d.extra<_SpotifyDeps>('spotify') != null,
  // Any Spotify Connect device works; the app is only needed to wake the
  // phone's own player.
  requiredApp: KnownApps.spotify.optional(
    'Spotify-App fehlt: Wiedergabe nur auf anderen Geräten',
  ),
  create: (d) {
    final deps = d.extra<_SpotifyDeps>('spotify')!;
    return SpotifyIntegration(
      deps.api,
      deps.secrets,
      launcher: deps.launcher,
      hostDevice: deps.hostDevice,
      // Spotify's own media session proves playback on the phone.
      media: d.ports.media,
      delay: deps.delay,
      // Events only (device choice, check result), no titles or names.
      onDiagnostic: devLog,
      onError: (_, kind) => d.reportError?.call('spotify', pausedError, kind),
      onRecovered: () => d.clearError?.call('spotify'),
    );
  },
  retry: (
    run: (i) async => i is SpotifyIntegration
        ? i.reconnect()
        : const ReconnectFailure(
            'spotify',
            PortErrorKind.permissionDenied,
            'Spotify ist nicht eingerichtet.',
          ),
  ),
);
