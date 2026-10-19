import 'package:wendelin_integrations/common.dart'
    show PortErrorKind, ReconnectFailure;
import 'package:wendelin_integrations/spotify.dart';

import '../app_requirements.dart';
import '../core_providers.dart';
import '../spotify.dart';
import 'integration_spec.dart';

typedef _SpotifyDeps = ({
  SpotifyApi api,
  SpotifySecrets secrets,
  SpotifyAppLauncher launcher,
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
      onError: (message) => d.reportError?.call('spotify', pausedError),
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
