import 'dart:async';
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

String _liveName(String engine, String modelId) =>
    'app.wendelin/whisper-live/$engine/$modelId';

const _engines = ['app', 'overlay', 'recognizer'];

/// Marks the own Whisper model [modelId] of [engine] as loaded (debug
/// counter of the loaded models per process, B14).
void markLiveWhisper(String engine, String modelId, SendPort port) {
  final name = _liveName(engine, modelId);
  IsolateNameServer.removePortNameMapping(name);
  IsolateNameServer.registerPortWithName(port, name);
}

/// Removes the mark of [markLiveWhisper].
void unmarkLiveWhisper(String engine, String modelId) =>
    IsolateNameServer.removePortNameMapping(_liveName(engine, modelId));

/// Number of Whisper models the engines of this process have loaded (by
/// their marks; an engine that ended without releasing still counts).
int liveWhisperCount([
  Iterable<String> modelIds = const ['whisper-base', 'whisper-small'],
]) => [
  for (final e in _engines)
    for (final id in modelIds)
      if (IsolateNameServer.lookupPortByName(_liveName(e, id)) != null) id,
].length;

// Users of a shared model (WP146): the engine that borrows another engine's
// model marks its use under a name; the owner does not free the model while
// such a mark answers. A mark of an engine that ended without unmarking does
// not answer and does not count.

String _useName(String engine, String modelId) =>
    'app.wendelin/whisper-use/$engine/$modelId';

String _ownerName(String modelId) => 'app.wendelin/whisper-owner/$modelId';

final _useChannels = <String, ReceivePort>{};

/// Marks that [engine] uses the model [modelId] of another engine.
void markWhisperUse(String engine, String modelId) {
  final name = _useName(engine, modelId);
  _useChannels.remove(name)?.close();
  final port = ReceivePort();
  port.listen((message) {
    if (message case [_, final SendPort reply]) reply.send('pong');
  });
  _useChannels[name] = port;
  IsolateNameServer.removePortNameMapping(name);
  IsolateNameServer.registerPortWithName(port.sendPort, name);
}

/// Removes the mark of [markWhisperUse] and tells the owner of the model.
void unmarkWhisperUse(String engine, String modelId) {
  final name = _useName(engine, modelId);
  IsolateNameServer.removePortNameMapping(name);
  _useChannels.remove(name)?.close();
  IsolateNameServer.lookupPortByName(_ownerName(modelId))?.send('left');
}

/// Number of other engines that currently use the model [modelId] (their mark
/// answers within [within]).
Future<int> whisperUsers(
  String modelId,
  String exceptEngine, {
  Duration within = const Duration(milliseconds: 500),
}) async {
  var n = 0;
  for (final e in _engines) {
    if (e == exceptEngine) continue;
    final port = IsolateNameServer.lookupPortByName(_useName(e, modelId));
    if (port == null) continue;
    final reply = ReceivePort();
    try {
      port.send(['ping', reply.sendPort]);
      await reply.first.timeout(within);
      n++;
    } on TimeoutException {
      // Dead mark.
    } finally {
      reply.close();
    }
  }
  return n;
}

final _ownerChannels = <String, ReceivePort>{};

/// The owner of [modelId] wants to hear when a user leaves ([onLeft]).
void watchWhisperUsers(String modelId, void Function() onLeft) {
  _ownerChannels.remove(modelId)?.close();
  final port = ReceivePort();
  port.listen((_) => onLeft());
  _ownerChannels[modelId] = port;
  IsolateNameServer.removePortNameMapping(_ownerName(modelId));
  IsolateNameServer.registerPortWithName(port.sendPort, _ownerName(modelId));
}

/// Ends [watchWhisperUsers].
void unwatchWhisperUsers(String modelId) {
  IsolateNameServer.removePortNameMapping(_ownerName(modelId));
  _ownerChannels.remove(modelId)?.close();
}
