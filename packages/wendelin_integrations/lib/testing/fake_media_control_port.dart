import '../src/common/port_exception.dart';
import '../src/media/media_port.dart';
import 'fake_failures.dart';

/// In-memory [MediaControlPort] with one player. Without [access] the
/// session calls throw `permissionDenied` and only [send] works (like the
/// media-key fallback).
final class FakeMediaControlPort with FakeFailures implements MediaControlPort {
  /// Creates the fake; [snapshot] is the active player (`null` = none).
  FakeMediaControlPort({
    this.access = true,
    this.snapshot,
    this.seekable = true,
    Iterable<String> openable = const [audiblePackage],
  }) : openable = {...openable};

  /// Whether the notification access is granted.
  bool access;

  /// The active session, or `null`.
  MediaSnapshot? snapshot;

  /// Whether the player accepts [seekTo].
  bool seekable;

  /// Packages [openApp] can open.
  final Set<String> openable;

  /// Commands sent, in order.
  final List<MediaCommand> sent = [];

  /// Positions sought, in order.
  final List<Duration> seeks = [];

  /// Apps opened, as `package` or `package?query`, in order.
  final List<String> opened = [];

  /// How often the settings page was opened.
  int settingsOpened = 0;

  @override
  Future<bool> hasSessionAccess() async {
    enter('hasSessionAccess');
    return access;
  }

  @override
  Future<void> openSessionAccessSettings() async {
    enter('openSessionAccessSettings');
    settingsOpened++;
  }

  @override
  Future<MediaSnapshot?> nowPlaying() async {
    enter('nowPlaying');
    _needAccess();
    return snapshot;
  }

  @override
  Future<void> send(MediaCommand command) async {
    enter('send');
    sent.add(command);
    final s = snapshot;
    if (s == null) return;
    if (command == MediaCommand.play || command == MediaCommand.pause) {
      snapshot = MediaSnapshot(
        packageName: s.packageName,
        appName: s.appName,
        playing: command == MediaCommand.play,
        title: s.title,
        artist: s.artist,
        album: s.album,
        positionMs: s.positionMs,
        durationMs: s.durationMs,
      );
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    enter('seekTo');
    _needAccess();
    final s = snapshot;
    if (s == null) {
      throw const PortException(
        PortErrorKind.notFound,
        'Gerade läuft nichts, das sich spulen ließe.',
      );
    }
    if (!seekable) {
      throw const PortException(
        PortErrorKind.unsupported,
        'Dieser Player lässt kein Spulen zu.',
      );
    }
    seeks.add(position);
    snapshot = MediaSnapshot(
      packageName: s.packageName,
      appName: s.appName,
      playing: s.playing,
      title: s.title,
      artist: s.artist,
      album: s.album,
      positionMs: position.inMilliseconds,
      durationMs: s.durationMs,
    );
  }

  @override
  Future<void> openApp(String androidPackage, {String? searchQuery}) async {
    enter('openApp');
    if (!openable.contains(androidPackage)) {
      throw const PortException(
        PortErrorKind.notFound,
        'Die App ist nicht installiert.',
      );
    }
    opened.add(
      searchQuery == null ? androidPackage : '$androidPackage?$searchQuery',
    );
  }

  void _needAccess() {
    if (!access) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Dafür braucht Wendelin den Benachrichtigungszugriff '
        '(Einstellungen → Integrationen → Medien).',
      );
    }
  }
}
