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
  final _voiceLocales = <String, String>{};

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
      return engines is List && engines.isNotEmpty;
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
        _voiceLocales[name] = locale;
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
      if (voice != null) {
        if (_voiceCache == null) await voices();
        final locale = _voiceLocales[voice];
        if (locale != null) {
          await _tts.setVoice({'name': voice, 'locale': locale});
        }
      } else if (language != null) {
        await _tts.setLanguage(language);
      }
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
