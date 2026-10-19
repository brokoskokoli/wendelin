import 'package:wendelin_core/wendelin_core.dart';

import '../common/app_presence.dart';
import 'media_port.dart';
import 'media_tools.dart';

/// Media control: `media__now_playing`, `media__play`, `media__pause`,
/// `media__next`, `media__previous`, `media__seek`, `media__open_audible`.
final class MediaIntegration implements Integration {
  /// Creates the integration on [port]; [apps] tells whether Audible is
  /// installed.
  MediaIntegration(this.port, this.apps);

  /// The active media player.
  final MediaControlPort port;

  /// Installed-app check (Audible).
  final AppPresencePort apps;

  /// Step id of the notification access.
  static const accessStep = 'notification_access';

  @override
  String get id => 'media';

  @override
  String get displayName => 'Medien';

  @override
  String get iconId => 'media';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// What the user listens to is personal; the tools are only sent to
  /// providers meeting the privacy level.
  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  /// Optional: without notification access only play/pause/next/previous
  /// (media keys) and „open Audible“ work.
  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: accessStep,
      kind: SetupStepKind.permission,
      label: 'Benachrichtigungszugriff erlauben (für „Was läuft?“ und Spulen)',
      optional: true,
    ),
  ];

  @override
  Future<SetupState> setupState() async {
    final granted = await port.hasSessionAccess();
    return SetupState(missingSteps: granted ? const [] : const [accessStep]);
  }

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    NowPlayingTool(port),
    MediaCommandTool(port, MediaCommand.play),
    MediaCommandTool(port, MediaCommand.pause),
    MediaCommandTool(port, MediaCommand.next),
    MediaCommandTool(port, MediaCommand.previous),
    MediaSeekTool(port),
    OpenAudibleTool(port, apps),
  ]);
}
