part of 'voice_controller.dart';

/// The permission step of a start (WP158).
extension VoicePrepare on VoiceController {
  /// Runs [prepare]; `null` when the start may go on, else the text to show
  /// (refused, or the query failed: fail-closed, logged).
  Future<String?> _askPrepare(Future<bool> Function()? prepare, Ref ref) async {
    try {
      final allowed = await prepare?.call() ?? true;
      return allowed ? null : microphoneDeniedHint;
    } on Object catch (e) {
      voiceLog('start-failed', {'reason': 'prepare', 'error': errorCode(e)});
      return ref.mounted ? voiceErrorText(uiTexts(ref), e) : '';
    }
  }
}
