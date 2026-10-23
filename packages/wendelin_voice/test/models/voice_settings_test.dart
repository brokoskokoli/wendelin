import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('Standardwerte: whisper-small, Sprache der App', () {
    const s = VoiceSettings();
    expect(s.sttModel, 'whisper-small');
    expect(s.sttLanguage, VoiceSettings.followApp);
    expect(s.tts, TtsPreference.automatic);
    expect(s.ttsRate, 1.0);
    expect(s.minSpeechMs, 200);
    expect(s.vadThreshold, 0.5);
    expect(s.spokenVersion, SpokenVersion.off);
    // M4, Entscheidung 2: Gesprächsmodus aus, Frage noch nicht gestellt.
    expect(s.conversationMode, isFalse);
    expect(s.conversationAsked, isFalse);
    expect(s.conversationOfferPending, isFalse);
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
      spokenVersion: SpokenVersion.checked,
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
        'twoVersions': 1,
        'spokenVersion': 'weird',
        'conversationMode': 'an',
        'conversationAsked': 1,
        'bargeIn': 'laut',
      }),
      const VoiceSettings(),
    );
    expect(VoiceSettings.fromJson(const {}), const VoiceSettings());
  });

  test('Migration: alter Schalter twoVersions wird zur Stufe', () {
    expect(
      VoiceSettings.fromJson({'twoVersions': true}).spokenVersion,
      SpokenVersion.protected,
    );
    expect(
      VoiceSettings.fromJson({'twoVersions': false}).spokenVersion,
      SpokenVersion.off,
    );
    // The new key wins; the old key is not written any more.
    expect(
      VoiceSettings.fromJson({'twoVersions': true, 'spokenVersion': 'always'})
          .spokenVersion,
      SpokenVersion.always,
    );
    expect(const VoiceSettings().toJson().containsKey('twoVersions'), isFalse);
  });

  test('WP134: der alte Schlüssel stopClosesOverlay wird ignoriert', () {
    final s = VoiceSettings.fromJson({'stopClosesOverlay': false, 'vadThreshold': 0.4});
    expect(s.vadThreshold, 0.4);
    expect(s.toJson().containsKey('stopClosesOverlay'), isFalse);
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
      'spokenVersion': 'off',
      'conversationMode': false,
      'conversationAsked': false,
      'conversationOfferPending': false,
      'bargeIn': 'keywords',
      'keepModelLoaded': false,
    });
  });

  test('Sprecher je Sprache: speichern, lesen, Unbekanntes verwerfen', () {
    const s = VoiceSettings(sherpaSpeakers: {'en': 'bf_emma'});
    final back = VoiceSettings.fromJson(s.toJson());
    expect(back, s);
    expect(back.sherpaSpeakers, {'en': 'bf_emma'});
    expect(
      VoiceSettings.fromJson({
        'sherpaSpeakers': {'en': 'nope', 'fr': 'af_heart', 'de': 3},
      }).sherpaSpeakers,
      isEmpty,
    );
    expect(s.copyWith(keepModelLoaded: true).sherpaSpeakers, s.sherpaSpeakers);
    expect(s == const VoiceSettings(), isFalse);
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

  test('Sprechererkennung (WP92a): standardmäßig aus, Rundlauf', () {
    expect(const VoiceSettings().speakerRecognition, isFalse);
    expect(
      const VoiceSettings().toJson().containsKey('speakerRecognition'),
      isFalse,
    );
    final on = const VoiceSettings().copyWith(speakerRecognition: true);
    expect(VoiceSettings.fromJson(on.toJson()).speakerRecognition, isTrue);
    expect(on, isNot(const VoiceSettings()));
    expect(on.hashCode, isNot(const VoiceSettings().hashCode));
    expect(
      VoiceSettings.fromJson({'speakerRecognition': 'ja'}).speakerRecognition,
      isFalse,
    );
  });
}
