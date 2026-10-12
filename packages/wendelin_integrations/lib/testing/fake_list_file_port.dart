import '../src/common/port_exception.dart';
import '../src/lists/lists.dart';
import 'fake_failures.dart';

/// In-memory [ListFilePort]: [files] maps handles to content. Tests can
/// change [files] directly to simulate a parallel edit (e.g. by Obsidian
/// Sync). [readOnly] handles reject writes with `permissionDenied`.
final class FakeListFilePort with FakeFailures implements ListFilePort {
  /// Creates the fake with initial [files].
  FakeListFilePort({Map<String, String>? files, Set<String>? readOnly})
    : files = files ?? {},
      readOnly = readOnly ?? {};

  /// Current file contents by handle.
  final Map<String, String> files;

  /// Handles without write permission.
  final Set<String> readOnly;

  /// Number of [write] calls.
  int writes = 0;

  @override
  Future<String> read(String handle) async {
    enter('read');
    return files[handle] ??
        (throw PortException(
          PortErrorKind.notFound,
          'Datei „$handle“ gibt es nicht',
        ));
  }

  @override
  Future<void> write(String handle, String content) async {
    enter('write');
    if (readOnly.contains(handle)) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Kein Schreibzugriff auf die Listendatei. Bitte in den Einstellungen '
        'neu auswählen.',
      );
    }
    writes++;
    files[handle] = content;
  }

  @override
  Future<bool> exists(String handle) async {
    enter('exists');
    return files.containsKey(handle);
  }
}
