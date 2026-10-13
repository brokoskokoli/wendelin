import '../src/common/app_presence.dart';
import 'fake_failures.dart';

/// In-memory [AppPresencePort]: [installed] holds the package names of the
/// installed apps; tests add and remove apps with [install] / [uninstall].
final class FakeAppPresencePort with FakeFailures implements AppPresencePort {
  /// Creates the fake with the [installed] package names.
  FakeAppPresencePort({Iterable<String> installed = const []})
    : installed = {...installed};

  /// Package names of the installed apps.
  final Set<String> installed;

  /// Package names asked for, in order.
  final List<String> queries = [];

  /// Installs [androidPackage].
  void install(String androidPackage) => installed.add(androidPackage);

  /// Removes [androidPackage].
  void uninstall(String androidPackage) => installed.remove(androidPackage);

  @override
  Future<bool> isInstalled(String androidPackage) async {
    enter('isInstalled');
    checkAndroidPackage(androidPackage);
    queries.add(androidPackage);
    return installed.contains(androidPackage);
  }
}
