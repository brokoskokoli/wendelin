import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// [ClipboardPort] on Flutter's system clipboard (text only).
///
/// Android 10+ only lets the foreground app read the clipboard; the platform
/// then returns nothing or fails. A failing platform call becomes
/// `PortException(permissionDenied)` so the tool can explain it.
final class FlutterClipboardPort implements ClipboardPort {
  /// Creates the port.
  const FlutterClipboardPort();

  @override
  Future<String?> read() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } on PlatformException {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Die Zwischenablage kann gerade nicht gelesen werden '
        '(nur im Vordergrund erlaubt).',
      );
    }
  }

  @override
  Future<void> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      throw const PortException(
        PortErrorKind.failed,
        'Die Zwischenablage konnte nicht beschrieben werden.',
      );
    }
  }
}
