import 'package:wendelin_core/wendelin_core.dart';

import '../common/app_presence.dart';
import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import 'media_port.dart';

/// „1:05:09“ or „5:09“ for [ms] milliseconds.
String formatMediaTime(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Snapshot, or `null` if it cannot be read (no access, no player).
Future<MediaSnapshot?> _peek(MediaControlPort port) async {
  try {
    return await port.nowPlaying();
  } on PortException {
    return null;
  }
}

/// `media__now_playing` (read): app, title, position of the active player.
/// Titles come from third-party apps, so the result is untrusted content.
final class NowPlayingTool extends IntegrationTool {
  /// Creates the tool.
  const NowPlayingTool(this.port);

  /// The active media player.
  final MediaControlPort port;

  @override
  String get name => 'media__now_playing';

  @override
  String get description =>
      'Tell what is playing right now on the phone (audiobook, podcast, '
      'music, video): app, title, author, position and length, and whether '
      'it is playing or paused.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final s = await port.nowPlaying();
    if (s == null) {
      return ToolOutcome.text(
        'Gerade läuft nichts (keine aktive Wiedergabe).',
        summary: 'Nichts spielt',
      );
    }
    final data = <String, Object?>{
      'app': s.appName,
      'playing': s.playing,
      'title': ?_clip(s.title),
      'artist': ?_clip(s.artist),
      'album': ?_clip(s.album),
      if (s.positionMs != null) 'position': formatMediaTime(s.positionMs!),
      if (s.durationMs != null) 'duration': formatMediaTime(s.durationMs!),
    };
    final what = s.title == null ? s.appName : ellipsize(s.title!, 60);
    return jsonOutcome(
      data,
      summary: '${s.playing ? 'Läuft' : 'Pausiert'}: $what (${s.appName})',
    );
  }

  static String? _clip(String? v) =>
      v == null || v.trim().isEmpty ? null : ellipsize(v, 200);

  @override
  String describe(ToolArgs args) => 'Anzeigen, was gerade läuft';

  @override
  String get fallbackDescription => describe(const ToolArgs({}));
}

/// `media__play`, `media__pause`, `media__next`, `media__previous` (write).
/// Play and pause undo each other; skipping has no undo (there is no
/// way back to the track that was skipped). The result holds no titles.
final class MediaCommandTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool for [command].
  const MediaCommandTool(this.port, this.command);

  /// The active media player.
  final MediaControlPort port;

  /// What the tool sends.
  final MediaCommand command;

  @override
  String get name => 'media__${command.name}';

  @override
  String get description => switch (command) {
    MediaCommand.play => 'Resume or start playback in the active media player.',
    MediaCommand.pause => 'Pause the active media player.',
    MediaCommand.next => 'Skip to the next track, episode or chapter.',
    MediaCommand.previous =>
      'Go back to the previous track, episode or chapter.',
  };

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final before = await _peek(port);
    final toggles =
        command == MediaCommand.play || command == MediaCommand.pause;
    final wantPlaying = command == MediaCommand.play;
    if (toggles && before != null && before.playing == wantPlaying) {
      return ToolOutcome.text(
        wantPlaying ? 'Es läuft schon.' : 'Es ist schon pausiert.',
        summary: wantPlaying ? 'Läuft schon' : 'Schon pausiert',
      );
    }
    await port.send(command);
    final opposite = wantPlaying ? MediaCommand.pause : MediaCommand.play;
    // Without session access only a media key is sent: the effect is not
    // known, so the result says "sent" instead of claiming a state.
    final unknown = toggles && before == null;
    return ToolOutcome.text(
      switch (command) {
        MediaCommand.play when unknown => 'Abspielen gesendet.',
        MediaCommand.pause when unknown => 'Pause gesendet.',
        MediaCommand.play => 'Die Wiedergabe läuft.',
        MediaCommand.pause => 'Die Wiedergabe ist pausiert.',
        MediaCommand.next => 'Weitergeschaltet zum nächsten Titel.',
        MediaCommand.previous => 'Zurückgeschaltet zum vorherigen Titel.',
      },
      summary: _summary,
      undo: toggles
          ? UndoAction(
              label: unknown
                  ? (wantPlaying ? 'Pause senden' : 'Abspielen senden')
                  : (wantPlaying ? 'Wieder pausieren' : 'Wieder abspielen'),
              run: () => port.send(opposite),
            )
          : null,
    );
  }

  String get _summary => switch (command) {
    MediaCommand.play => 'Wiedergabe gestartet',
    MediaCommand.pause => 'Wiedergabe pausiert',
    MediaCommand.next => 'Nächster Titel',
    MediaCommand.previous => 'Vorheriger Titel',
  };

  @override
  String describe(ToolArgs args) => switch (command) {
    MediaCommand.play => 'Wiedergabe starten',
    MediaCommand.pause => 'Wiedergabe pausieren',
    MediaCommand.next => 'Zum nächsten Titel springen',
    MediaCommand.previous => 'Zum vorherigen Titel springen',
  };

  @override
  String get fallbackDescription => describe(const ToolArgs({}));
}

/// `media__seek` (write): relative (`seconds`, negative = back) or
/// absolute (`position_seconds`). Undo jumps back to the old position.
final class MediaSeekTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool.
  const MediaSeekTool(this.port);

  /// The active media player.
  final MediaControlPort port;

  /// Longest jump accepted: 12 hours.
  static const maxSeconds = 12 * 3600;

  @override
  String get name => 'media__seek';

  @override
  String get description =>
      'Jump in the active media player. Give "seconds" to skip relative to '
      'the current position (negative = back, e.g. -30 for "30 seconds '
      'back"), or "position_seconds" for an absolute position from the '
      'start. Give exactly one of them.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'seconds': {
        'type': 'integer',
        'minimum': -maxSeconds,
        'maximum': maxSeconds,
        'description': 'Relative jump in seconds, negative goes back.',
      },
      'position_seconds': {
        'type': 'integer',
        'minimum': 0,
        'maximum': maxSeconds,
        'description': 'Absolute position in seconds from the start.',
      },
    },
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final delta = args.optInt('seconds', min: -maxSeconds, max: maxSeconds);
    final absolute = args.optInt('position_seconds', min: 0, max: maxSeconds);
    if ((delta == null) == (absolute == null)) {
      throw const InvalidArgumentsException(
        'genau eines von „seconds“ und „position_seconds“ angeben',
      );
    }
    final s = await port.nowPlaying();
    if (s == null) {
      throw const PortException(
        PortErrorKind.notFound,
        'Gerade läuft nichts, das sich spulen ließe.',
      );
    }
    final from = s.positionMs;
    if (from == null && absolute == null) {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dieser Player meldet keine Position, relatives Spulen geht nicht.',
      );
    }
    var target = absolute != null ? absolute * 1000 : from! + delta! * 1000;
    final length = s.durationMs;
    // Not exactly the end: many players jump to the next title there.
    if (length != null && length > 0) {
      final last = length > 1000 ? length - 1000 : 0;
      if (target > last) target = last;
    }
    if (target < 0) target = 0;
    await port.seekTo(Duration(milliseconds: target));
    return ToolOutcome.text(
      'Position jetzt ${formatMediaTime(target)}.',
      summary: 'Gespult auf ${formatMediaTime(target)}',
      undo: from == null
          ? null
          : UndoAction(
              label: 'Zurück auf ${formatMediaTime(from)}',
              run: () => port.seekTo(Duration(milliseconds: from)),
            ),
    );
  }

  @override
  String describe(ToolArgs args) {
    final delta = args.optInt('seconds');
    final absolute = args.optInt('position_seconds');
    if (absolute != null) {
      return 'Springen auf ${formatMediaTime(absolute * 1000)}';
    }
    if (delta != null && delta != 0) {
      return '${delta.abs()} Sekunden ${delta < 0 ? 'zurück' : 'vor'}spulen';
    }
    return fallbackDescription;
  }

  @override
  String get fallbackDescription => 'In der Wiedergabe spulen';
}

/// `media__open_audible` (write): opens the Audible app, optionally with a
/// title search, only if it is installed.
final class OpenAudibleTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool.
  const OpenAudibleTool(this.port, this.apps);

  /// The active media player (opens apps).
  final MediaControlPort port;

  /// Installed-app check.
  final AppPresencePort apps;

  @override
  String get name => 'media__open_audible';

  @override
  String get description =>
      'Open the Audible app. With "query" it searches for that book title or '
      'author and starts playing the best match right away; without it only '
      'the app opens (start playback afterwards with media__play). Only '
      'works if Audible is installed.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'query': {
        'type': 'string',
        'description': 'Book title or author to search for (optional).',
        'maxLength': 200,
      },
    },
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final query = args.optString('query');
    if (!await apps.isInstalled(audiblePackage)) {
      throw const PortException(
        PortErrorKind.notFound,
        'Audible ist nicht installiert.',
      );
    }
    final search = query == null || query.isEmpty ? null : query;
    await port.openApp(audiblePackage, searchQuery: search);
    if (search != null) {
      return ToolOutcome.text(
        'Audible ist geöffnet, die Suche nach „${ellipsize(search, 60)}“ '
        'läuft; was Audible findet, spielt direkt ab.',
        summary: 'Audible: „${ellipsize(search, 40)}“ gesucht',
      );
    }
    return ToolOutcome.text(
      'Audible ist geöffnet.',
      summary: 'Audible geöffnet',
    );
  }

  @override
  String describe(ToolArgs args) {
    final query = args.optString('query');
    return query == null || query.isEmpty
        ? 'Audible öffnen'
        : 'Audible öffnen, „${ellipsize(query, 60)}“ suchen und abspielen';
  }

  @override
  String get fallbackDescription => 'Audible öffnen';
}
