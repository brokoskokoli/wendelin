import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// System speech output (Android `TextToSpeech`) via `flutter_tts`.
///
/// - [isAvailable] is true only if a TTS engine is installed (a de-Googled
///   device may have none, K7); then `TtsSelector` falls back to sherpa.
/// - [voices] leaves out voices that need the network: the text of an
///   answer must not leave the device without the user choosing a cloud
///   service (concept: Sicherheit).
/// - [speak] always sets an offline voice explicitly: [voice] if it is
///   one, otherwise the first offline voice of the language. Without one it
///   throws `VoiceException(unavailable)` instead of using the engine
///   default; [isAvailable] is false without any offline voice, so
///   `TtsSelector` uses the sherpa voice.
/// - Utterances run one after the other; [stop] ends the current one and
///   drops the waiting ones. Rate 1.0 is the engine's normal speed.
final class SystemTextToSpeech implements TextToSpeech {
  /// Creates the engine; [tts] is injectable for tests.
  SystemTextToSpeech({
    FlutterTts? tts,
    this.timeout = const Duration(minutes: 2),
  }) : _given = tts;

  final FlutterTts? _given;
  late final FlutterTts _tts = _given ?? FlutterTts();

  /// Safety limit for one utterance (the engine may never report the end).
  final Duration timeout;

  final _states = StreamController<TtsState>.broadcast(sync: true);
  TtsState _state = TtsState.idle;
  Future<void>? _setup;
  Future<void> _queue = Future.value();
  int _generation = 0;
  List<TtsVoice>? _voiceCache;

  @override
  TtsState get state => _state;

  @override
  Stream<TtsState> get states => _states.stream;

  void _set(TtsState s) {
    if (_state == s) return;
    _state = s;
    _states.add(s);
  }

  Future<void> _ensureSetup() => _setup ??= _tts.awaitSpeakCompletion(true);

  @override
  Future<bool> get isAvailable async {
    try {
      final engines = await _tts.getEngines;
      // Without an offline voice it would have to use the network.
      return engines is List &&
          engines.isNotEmpty &&
          (await voices()).isNotEmpty;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<TtsVoice>> voices() async {
    final cached = _voiceCache;
    if (cached != null) return cached;
    final raw = await _tts.getVoices;
    final result = <TtsVoice>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is! Map) continue;
        final name = v['name']?.toString();
        final locale = v['locale']?.toString();
        if (name == null || name.isEmpty || locale == null || locale.isEmpty) {
          continue;
        }
        if (v['network_required']?.toString() == '1') continue;
        result.add(TtsVoice(id: name, language: locale, name: name));
      }
    }
    return _voiceCache = List.unmodifiable(result);
  }

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) {
    if (rate <= 0) throw ArgumentError.value(rate, 'rate', 'muss > 0 sein');
    if (text.trim().isEmpty) return Future.value();
    final generation = _generation;
    final run = _queue.then((_) async {
      if (generation != _generation) return; // stopped while waiting
      await _ensureSetup();
      // Always an explicit offline voice: the engine default could be a
      // network voice and send the answer text off the device.
      final chosen = offlineVoiceFor(await voices(), voice, language);
      if (chosen == null) {
        throw VoiceException(
          VoiceErrorKind.unavailable,
          'Die Systemstimme hat keine Offline-Stimme'
          '${language == null ? '' : ' für „$language“'}.',
        );
      }
      await _tts.setVoice({'name': chosen.id, 'locale': chosen.language});
      // flutter_tts: 0.5 is the normal rate on every platform.
      await _tts.setSpeechRate((rate * 0.5).clamp(0.05, 1.0));
      if (generation != _generation) return;
      _set(TtsState.speaking);
      try {
        await _tts.speak(text).timeout(timeout);
      } on TimeoutException {
        await _tts.stop();
      } finally {
        _set(TtsState.idle);
      }
    });
    _queue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<void> stop() async {
    _generation++;
    if (_state == TtsState.idle) return;
    try {
      await _tts.stop();
    } on Object {
      // Engine already gone: the speak future ends via its timeout.
    }
  }
}

/// The offline voice to use: [id] if it is in [voices], otherwise the first
/// voice of [language] (primary subtag; any voice without [language]).
TtsVoice? offlineVoiceFor(List<TtsVoice> voices, String? id, String? language) {
  for (final v in voices) {
    if (v.id == id) return v;
  }
  String primary(String tag) => tag.split(RegExp('[-_]')).first.toLowerCase();
  for (final v in voices) {
    if (language == null || primary(v.language) == primary(language)) {
      return v;
    }
  }
  return null;
}
