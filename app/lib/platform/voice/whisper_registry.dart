import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'whisper_share.dart';

/// Process-wide name of the shared Whisper model [modelId].
String sharedWhisperName(String modelId) => 'app.wendelin/whisper/$modelId';

/// Offers the Whisper isolate behind [port] (model [modelId]) to the other
/// Flutter engines of the process (ADR 0008). A previous entry is replaced.
void publishSharedWhisper(String modelId, SendPort port) {
  final name = sharedWhisperName(modelId);
  IsolateNameServer.removePortNameMapping(name);
  IsolateNameServer.registerPortWithName(port, name);
}

/// Withdraws [port] again (only if it is still the published one).
void withdrawSharedWhisper(String modelId, SendPort port) {
  final name = sharedWhisperName(modelId);
  if (IsolateNameServer.lookupPortByName(name) == port) {
    IsolateNameServer.removePortNameMapping(name);
  }
}

/// The Whisper model [modelId] another engine has loaded, if it answers
/// within [within]; `null` otherwise (none published, owner gone or busy).
Future<RemoteWhisperBackend?> lookupSharedWhisper(
  String modelId, {
  Duration within = const Duration(seconds: 3),
}) async {
  final port = IsolateNameServer.lookupPortByName(sharedWhisperName(modelId));
  if (port == null) return null;
  if (!await RemoteWhisperBackend.alive(port, within: within)) return null;
  return RemoteWhisperBackend(port);
}
