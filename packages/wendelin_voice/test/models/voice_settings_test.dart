import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('Standardwerte: whisper-small, Sprache der App, Stopp schließt', () {
    const s = VoiceSettings();
    expect(s.sttModel, 'whisper-small');
    expect(s.sttLanguage, VoiceSettings.followApp);
    expect(s.tts, TtsPreference.automatic);
    expect(s.ttsRate, 1.0);
    expect(s.minSpeechMs, 200);
    expect(s.vadThreshold, 0.5);
    expect(s.stopClosesOverlay, isTrue);
    expect(s.twoVersions, isFalse);
    // M4, Entscheidung 2: Gesprächsmodus aus, Frage noch nicht gestellt.
    expect(s.conversationMode, isFalse);
    expect(s.conversationAsked, isFalse);
    expect(s.bargeIn, BargeInMode.keywords);
    expect(s.endpoint.minSpeech, const Duration(milliseconds: 200));
  });

  test('JSON hin und zurück, ungültige Werte fallen auf Standard', () {
    const s = VoiceSettings(
      sttModel: 'whisper-base',
      sttLanguage: 'fr',
      tts: TtsPreference.system,
      ttsVoice: 'v',
      ttsRate: 1.5,
      minSpeechMs: 300,
      vadThreshold: 0.4,
      stopClosesOverlay: false,
      twoVersions: true,
      conversationMode: true,
      conversationAsked: true,
      bargeIn: BargeInMode.speech,
    );
    expect(VoiceSettings.fromJson(s.toJson()), s);
    expect(s.hashCode, VoiceSettings.fromJson(s.toJson()).hashCode);
    expect(s.toJson().containsKey('ttsVoice'), isTrue);
    expect(const VoiceSettings().toJson().containsKey('ttsVoice'), isFalse);
    expect(
      VoiceSettings.fromJson({
        'sttModel': 'evil',
        'sttLanguage': 'xx',
        'tts': 'loud',
        'ttsVoice': '',
        'ttsRate': 9,
        'minSpeechMs': 5,
        'vadThreshold': 1.5,
        'stopClosesOverlay': 'ja',
        'twoVersions': 1,
        'conversationMode': 'an',
        'conversationAsked': 1,
        'bargeIn': 'laut',
      }),
      const VoiceSettings(),
    );
    expect(VoiceSettings.fromJson(const {}), const VoiceSettings());
  });

  test('Das JSON-Format ist festgeschrieben', () {
    expect(const VoiceSettings(ttsVoice: 'v').toJson(), {
      'sttModel': 'whisper-small',
      'sttLanguage': 'app',
      'tts': 'automatic',
      'ttsVoice': 'v',
      'ttsRate': 1.0,
      'minSpeechMs': 200,
      'vadThreshold': 0.5,
      'stopClosesOverlay': true,
      'twoVersions': false,
      'conversationMode': false,
      'conversationAsked': false,
      'bargeIn': 'keywords',
    });
  });

  test('Sprache und copyWith', () {
    const s = VoiceSettings(ttsVoice: 'v');
    expect(s.effectiveLanguage('de'), 'de');
    expect(
      const VoiceSettings(sttLanguage: VoiceSettings.detect)
          .effectiveLanguage('de'),
      isNull,
    );
    expect(
      const VoiceSettings(sttLanguage: 'fr').effectiveLanguage('de'),
      'fr',
    );
    expect(s.copyWith(clearVoice: true).ttsVoice, isNull);
    expect(s.copyWith(ttsRate: 1.2).ttsVoice, 'v');
    expect(s.copyWith(ttsRate: 1.2).ttsRate, 1.2);
    expect(s.copyWith(sttModel: 'whisper-base').sttModel, 'whisper-base');
    expect(s.copyWith(conversationMode: true).conversationMode, isTrue);
    expect(s.copyWith(conversationAsked: true).conversationAsked, isTrue);
    expect(s.copyWith(bargeIn: BargeInMode.off).bargeIn, BargeInMode.off);
  });
}
