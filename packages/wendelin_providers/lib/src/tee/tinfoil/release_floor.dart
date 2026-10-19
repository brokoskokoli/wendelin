import 'package:meta/meta.dart';

/// Version of a Tinfoil release tag (`v0.0.158`), comparable.
@immutable
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  /// Creates a version.
  const ReleaseVersion(this.major, this.minor, this.patch);

  /// Reads `v1.2.3` or `1.2.3`; `null` for anything else (pre-releases and
  /// suffixes included: a tag the app cannot order is not accepted).
  static ReleaseVersion? tryParse(String tag) {
    final m = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$').firstMatch(tag);
    if (m == null) return null;
    return ReleaseVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// Major part.
  final int major;

  /// Minor part.
  final int minor;

  /// Patch part.
  final int patch;

  @override
  int compareTo(ReleaseVersion other) {
    final a = major.compareTo(other.major);
    if (a != 0) return a;
    final b = minor.compareTo(other.minor);
    return b != 0 ? b : patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => 'v$major.$minor.$patch';
}

/// The newest release the app has ever verified for a profile (downgrade
/// protection, K59): the version and the time Rekor signed for it.
@immutable
final class ReleaseFloor {
  /// Creates the floor.
  const ReleaseFloor({required this.version, required this.integratedTime});

  /// Reads [toJson]; throws [FormatException].
  factory ReleaseFloor.fromJson(Map<String, Object?> json) {
    final tag = json['version'];
    final time = json['integratedTime'];
    final version = tag is String ? ReleaseVersion.tryParse(tag) : null;
    if (version == null || time is! int || time < 0) {
      throw const FormatException('ReleaseFloor: Felder fehlen');
    }
    return ReleaseFloor(version: version, integratedTime: time);
  }

  /// Highest release version seen.
  final ReleaseVersion version;

  /// Rekor entry time (Unix seconds) of that release.
  final int integratedTime;

  /// Whether a release with [candidate] and [time] is older than this
  /// floor: a lower version, or the same version with an earlier signing
  /// time.
  bool rejects(ReleaseVersion candidate, int time) {
    final c = candidate.compareTo(version);
    return c < 0 || (c == 0 && time < integratedTime);
  }

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'version': version.toString(),
    'integratedTime': integratedTime,
  };

  @override
  bool operator ==(Object other) =>
      other is ReleaseFloor &&
      other.version == version &&
      other.integratedTime == integratedTime;

  @override
  int get hashCode => Object.hash(version, integratedTime);
}

/// Persists the [ReleaseFloor] per provider profile (in the app through the
/// settings storage, like the pin).
abstract interface class ReleaseFloorStore {
  /// The floor of [profileId], `null` if none was set.
  Future<ReleaseFloor?> load(String profileId);

  /// Raises the floor of [profileId]. Callers only pass floors that are not
  /// lower than the stored one.
  Future<void> save(String profileId, ReleaseFloor floor);
}

/// In-memory [ReleaseFloorStore] for tests.
final class InMemoryReleaseFloorStore implements ReleaseFloorStore {
  final Map<String, ReleaseFloor> _floors = {};

  @override
  Future<ReleaseFloor?> load(String profileId) async => _floors[profileId];

  @override
  Future<void> save(String profileId, ReleaseFloor floor) async =>
      _floors[profileId] = floor;
}
