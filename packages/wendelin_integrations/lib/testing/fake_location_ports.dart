import '../src/common/port_exception.dart';
import '../src/location/location_port.dart';
import '../src/maps/navigation_apps.dart';
import 'fake_failures.dart';

/// In-memory [LocationPort]: without [permission] `current` throws
/// `permissionDenied`; [fix] `null` means „no fix“ (`unavailable`).
final class FakeLocationPort with FakeFailures implements LocationPort {
  /// Creates the fake.
  FakeLocationPort({
    this.permission = true,
    this.fix = const GeoFix(
      latitude: 53.5511,
      longitude: 9.9937,
      accuracyMeters: 12,
      placeName: 'Hamburg',
    ),
  });

  /// Whether the permission is granted.
  bool permission;

  /// Whether [requestPermission] grants it.
  bool grantOnRequest = true;

  /// The current fix, `null` = none.
  GeoFix? fix;

  /// How often the permission was requested.
  int requests = 0;

  @override
  Future<bool> hasPermission() async {
    enter('hasPermission');
    return permission;
  }

  @override
  Future<bool> requestPermission() async {
    enter('requestPermission');
    requests++;
    if (grantOnRequest) permission = true;
    return permission;
  }

  @override
  Future<GeoFix> current() async {
    enter('current');
    if (!permission) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Kein Zugriff auf den Standort. Bitte in den Einstellungen erlauben.',
      );
    }
    return fix ??
        (throw const PortException(
          PortErrorKind.unavailable,
          'Gerade kein Standort verfügbar. Ist der Standort eingeschaltet?',
        ));
  }
}

/// [MapsLauncherPort] that records the launches. Packages in [missing] act
/// as not installed (`notFound`); with [anyApp] false `geo:` fails too.
final class FakeMapsLauncherPort with FakeFailures implements MapsLauncherPort {
  /// Creates the fake.
  FakeMapsLauncherPort({
    this.anyApp = true,
    Iterable<String> missing = const [],
  }) : missing = {...missing};

  /// Whether an app handles intents without a package.
  bool anyApp;

  /// Packages that are not installed.
  final Set<String> missing;

  /// Successful launches, in order.
  final List<MapsLaunch> launched = [];

  @override
  Future<void> launch(MapsLaunch launch) async {
    enter('launch');
    final package = launch.package;
    final handled = package == null ? anyApp : !missing.contains(package);
    if (!handled) {
      throw const PortException(PortErrorKind.notFound, 'Keine Karten-App.');
    }
    launched.add(launch);
  }
}

/// In-memory [NavigationApps]: [active] and [preferred] are set by the test,
/// [installed] holds the apps the live check finds.
final class FakeNavigationApps with FakeFailures implements NavigationApps {
  /// Creates the fake; by default Google Maps and Waze are on and installed.
  FakeNavigationApps({
    Set<NavigationApp>? active,
    Set<NavigationApp>? installed,
    this.preferred,
  }) : active = active ?? {...NavigationApp.values},
       installed = installed ?? {...NavigationApp.values};

  @override
  Set<NavigationApp> active;

  @override
  NavigationApp? preferred;

  /// Apps the live check finds installed.
  final Set<NavigationApp> installed;

  @override
  Future<bool> isInstalled(NavigationApp app) async {
    enter('isInstalled');
    return installed.contains(app);
  }
}
