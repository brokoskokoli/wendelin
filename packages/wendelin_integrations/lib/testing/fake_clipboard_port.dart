import '../src/clipboard/clipboard.dart';
import '../src/common/port_exception.dart';
import 'fake_failures.dart';

/// In-memory [ClipboardPort]. With [foreground] `false`, [read] throws
/// `permissionDenied` like Android 10+ in the background.
final class FakeClipboardPort with FakeFailures implements ClipboardPort {
  /// Creates the fake with initial [content].
  FakeClipboardPort({this.content, this.foreground = true});

  /// Current clipboard text.
  String? content;

  /// Whether the app is in the foreground (reading allowed).
  bool foreground;

  @override
  Future<String?> read() async {
    enter('read');
    if (!foreground) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Die Zwischenablage kann nur gelesen werden, wenn die App geöffnet ist',
      );
    }
    return content;
  }

  @override
  Future<void> write(String text) async {
    enter('write');
    content = text;
  }
}
