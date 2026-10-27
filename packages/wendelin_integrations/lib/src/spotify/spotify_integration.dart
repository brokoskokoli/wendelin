import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'spotify_api.dart';
import 'spotify_session.dart';
import 'spotify_tools.dart';

/// Android package of the Spotify app (wake-up, app detection).
const spotifyAndroidPackage = 'com.spotify.music';

/// Spotify playback (`spotify__…` tools) over the Web API.
///
/// [onError] / [onRecovered] connect the error state to the app (usually
/// `ToolRegistry.reportError` / `clearError`); see [SpotifySession].
final class SpotifyIntegration implements Integration {
  /// Creates the integration.
  SpotifyIntegration(
    SpotifyApi api,
    this.secrets, {
    SpotifyAppLauncher? launcher,
    SpotifyHostDevice? hostDevice,
    void Function(String event, Map<String, Object> fields)? onDiagnostic,
    void Function(String message, PortErrorKind kind)? onError,
    void Function()? onRecovered,
    SpotifyDelay? delay,
  }) : session = SpotifySession(
         api,
         secrets,
         launcher: launcher,
         hostDevice: hostDevice,
         onDiagnostic: onDiagnostic,
         onError: onError,
         onRecovered: onRecovered,
         delay: delay,
       );

  /// Id of the setup step „Spotify login“.
  static const loginStep = 'spotify_login';

  /// Client-ID and tokens.
  final SpotifySecrets secrets;

  /// Token handling shared by the tools.
  final SpotifySession session;

  @override
  String get id => 'spotify';

  @override
  String get displayName => 'Spotify';

  @override
  String get iconId => 'music';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(id: loginStep, kind: SetupStepKind.login, label: 'Login fehlt'),
  ];

  @override
  Future<SetupState> setupState() async =>
      SetupState(missingSteps: [if (await secrets.auth() == null) loginStep]);

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    SpotifySearchTool(session),
    SpotifyPlayTool(session),
    SpotifyPauseTool(session),
    SpotifyNextTool(session),
    SpotifyPreviousTool(session),
    SpotifyNowPlayingTool(session),
    SpotifyQueueAddTool(session),
  ]);

  /// Tests the connection (renews the token if needed, reads the playback
  /// state). Returns `null` on success, else the failure (the app words it).
  Future<ReconnectFailure?> reconnect() async {
    try {
      await session.run(session.api.playback);
      return null;
    } on PortException catch (e) {
      return ReconnectFailure.of('spotify', e);
    }
  }

  /// Forgets the cached tokens (call after the login changed).
  Future<void> signOut() => session.forget();
}
