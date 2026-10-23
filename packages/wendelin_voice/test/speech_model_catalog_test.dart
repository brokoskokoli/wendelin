import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  const catalog = SpeechModelCatalog.standard;

  test('enthält Whisper base/small, Silero VAD und Stimmen de/fr/en', () {
    expect(catalog.ofKind(SpeechModelKind.stt).map((m) => m.id), [
      'whisper-base',
      'whisper-small',
      'parakeet-tdt-0.6b-v3',
      'canary-180m-flash',
    ]);
    for (final m in catalog.ofKind(SpeechModelKind.stt)) {
      expect(m.languages, containsAll(['de', 'fr', 'en']));
    }
    expect(catalog.ofKind(SpeechModelKind.vad).single.id, 'silero-vad');
    expect(catalog.voiceFor('de-DE')?.id, 'tts-de-thorsten');
    expect(catalog.voiceFor('fr')?.id, 'tts-fr-siwis');
    expect(catalog.voiceFor('en_US')?.id, 'tts-en-ljspeech');
    expect(catalog.voiceFor('it'), isNull);
    expect(
      catalog.byId('whisper-small'),
      same(SpeechModelCatalog.whisperSmall),
    );
    expect(catalog.byId('gibt-es-nicht'), isNull);
  });

  test('jede Datei hat https-URL, Größe und SHA-256', () {
    final ids = <String>{};
    for (final m in catalog.models) {
      expect(ids.add(m.id), isTrue, reason: 'doppelte Id ${m.id}');
      expect(m.files, isNotEmpty);
      expect(m.license, isNotEmpty);
      expect(m.source, isNotEmpty);
      final names = <String>{};
      for (final f in m.files) {
        expect(names.add(f.name), isTrue);
        expect(f.name, isNot(contains('/')));
        expect(Uri.parse(f.url).scheme, 'https');
        expect(f.url, endsWith('/${f.name}'));
        expect(f.sizeBytes, greaterThan(0));
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      expect(m.sizeBytes, m.files.fold<int>(0, (n, f) => n + f.sizeBytes));
      expect(m.toString(), contains(m.id));
    }
  });

  test('Whisper-URLs sind auf einen Commit gepinnt', () {
    for (final m in catalog.ofKind(SpeechModelKind.stt)) {
      if (m.engine != SttEngine.whisper) continue;
      for (final f in m.files) {
        expect(f.url, matches(RegExp(r'/resolve/[0-9a-f]{40}/')));
        expect(f.archive, ModelArchive.none);
      }
    }
  });

  test('NeMo-Modelle: Engine im Katalog, Archiv, CC-BY, Größe und RAM', () {
    const p = SpeechModelCatalog.parakeetV3;
    const c = SpeechModelCatalog.canary180m;
    expect(p.engine, SttEngine.nemoTransducer);
    expect(c.engine, SttEngine.canary);
    expect(p.supportsHotwords, isTrue);
    expect(c.supportsHotwords, isFalse);
    expect(SpeechModelCatalog.whisperSmall.engine, SttEngine.whisper);
    expect(SpeechModelCatalog.whisperSmall.supportsHotwords, isFalse);
    for (final m in [p, c]) {
      expect(m.files.single.archive, ModelArchive.tarBz2);
      expect(m.files.single.url, contains('/asr-models/'));
      expect(m.license, contains('CC-BY-4.0'));
      expect(m.attribution, contains('CC BY 4.0'));
      expect(m.ramBytes, greaterThan(500 * 1024 * 1024));
    }
    expect(p.sizeBytes, 487170055);
    expect(c.sizeBytes, 153692328);
    // Whisper small bleibt Standard.
    expect(const VoiceSettings().sttModel, SpeechModelCatalog.whisperSmall.id);
  });

  test('Ramona und Eva: M-AILABS-Lizenz mit Attribution, echte Prüfsumme', () {
    const sums = {
      'tts-de-ramona':
          'e532ddcbb09c16a65f56441bbbbf301083d2ea5b18ce937775303942f2b7a8f4',
      'tts-de-eva':
          '0501123c7e184571a40690e79943f4111a57b988632f7f60a9d2344fd061e2a2',
    };
    for (final MapEntry(:key, :value) in sums.entries) {
      final m = catalog.byId(key)!;
      expect(m.files.single.sha256, value, reason: key);
      expect(m.gender, VoiceGender.female);
      expect(m.languages, {'de'});
      expect(m.license, contains('M-AILABS'));
      expect(m.attribution, contains('M-AILABS'));
      expect(m.sizeBytes, lessThan(25000000));
      expect(m.note, contains('selbst gehasht'));
      expect(catalog.voicesFor('de').map((v) => v.id), contains(key));
    }
  });

  test('Größe und Dateiname der TTS-Archive sind festgenagelt', () {
    const files = {
      'tts-de-ramona': ('vits-piper-de_DE-ramona-low-int8.tar.bz2', 21199380),
      'tts-de-eva': ('vits-piper-de_DE-eva_k-x_low-int8.tar.bz2', 13321491),
      'tts-de-kerstin': ('vits-piper-de_DE-kerstin-low-int8.tar.bz2', 21174728),
      'tts-fr-gilles': ('vits-piper-fr_FR-gilles-low-int8.tar.bz2', 21248965),
      'tts-en-joe': ('vits-piper-en_US-joe-medium-int8.tar.bz2', 21230019),
    };
    for (final MapEntry(:key, :value) in files.entries) {
      final f = catalog.byId(key)!.files.single;
      expect(f.name, value.$1, reason: key);
      expect(f.sizeBytes, value.$2, reason: key);
    }
  });

  test('Pflicht-Attribution für SIWIS, englische Stimme gemeinfrei', () {
    expect(SpeechModelCatalog.voiceFr.attribution, contains('SIWIS'));
    expect(SpeechModelCatalog.voiceFr.attribution, contains('CC BY 4.0'));
    expect(SpeechModelCatalog.voiceEn.license, contains('Public Domain'));
    expect(SpeechModelCatalog.whisperBase.attribution, isNull);
  });

  test('je Sprache mindestens eine weibliche und eine männliche Stimme', () {
    for (final lang in ['de', 'fr', 'en']) {
      final voices = catalog.voicesFor(lang);
      expect(
        voices.map((v) => v.gender ?? v.speakers.first.gender),
        containsAll([VoiceGender.female, VoiceGender.male]),
        reason: lang,
      );
      expect(catalog.voiceFor(lang), voices.first, reason: 'Standard');
    }
    expect(catalog.voicesFor('fr-CA').map((v) => v.id), [
      'tts-fr-siwis',
      'tts-fr-gilles',
      'tts-kokoro',
    ]);
    expect(catalog.voicesFor('it'), isEmpty);
    expect(SpeechModelCatalog.whisperBase.gender, isNull);
  });

  test('Stimmen: freie Lizenz, echte Prüfsumme, Quelle gepinnt', () {
    const sums = {
      'tts-de-kerstin':
          'bcd8039667940cf2efc939b844f4b33d0823096572fcc1a8caaa2faa77f3379c',
      'tts-fr-gilles':
          '92d2bfd9b6b32b9787557c466b15620e453aecc10ec521762660e034941b3c43',
      'tts-en-joe':
          '644527f29eca0ada5595d7b6e4daf6388f5ac0c4870b4d42996a6687fcefeb37',
    };
    for (final MapEntry(:key, :value) in sums.entries) {
      final m = catalog.byId(key)!;
      expect(m.files.single.sha256, value, reason: key);
      expect(m.license, startsWith('CC0'));
      expect(m.sizeBytes, lessThan(25000000));
      expect(m.note, contains('selbst gehasht'));
    }
    for (final m in catalog.ofKind(SpeechModelKind.tts)) {
      expect(m.gender ?? m.speakers.first.gender, isNotNull, reason: m.id);
      if (m.synth == TtsSynth.piper) expect(m.languages, hasLength(1));
      expect(m.license, isNot(contains('NC')), reason: 'keine NC-Lizenz');
      expect(m.license, isNot(contains('GPL')));
    }
  });

  test(
    'Thorsten high (fp32) und Kokoro: Prüfsummen, Sprecher, Standard bleibt',
    () {
      final high = SpeechModelCatalog.voiceDeThorstenHigh;
      expect(high.files.single.name, 'vits-piper-de_DE-thorsten-high.tar.bz2');
      expect(high.files.single.sizeBytes, 115591546);
      expect(
        high.files.single.sha256,
        'dd4ed1b0d42c30a1a4862fc2b243e8044d52b8889c9ff3d1e99e92028888bc4a',
      );
      final k = SpeechModelCatalog.voiceKokoro;
      expect(k.files.single.sizeBytes, 132303094);
      expect(
        k.files.single.sha256,
        '4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e',
      );
      expect(k.synth, TtsSynth.kokoro);
      expect(k.languages, {'en', 'fr'});
      expect(k.speakersFor('en').map((s) => (s.id, s.sid)), [
        ('af_heart', 3),
        ('bf_emma', 21),
      ]);
      // 'en-gb' kennt die espeak-Datei des Modells nicht.
      expect(k.speakersFor('en').map((s) => s.espeakLang), ['en-us', 'en']);
      expect(k.speakersFor('fr').single.id, 'ff_siwis');
      expect(k.speakersFor('de'), isEmpty);
      expect(k.attribution, contains('SIWIS'));
      // Piper medium/low bleibt Standard; nichts mit NC, kein lessac.
      expect(catalog.voiceFor('de')!.id, 'tts-de-thorsten');
      expect(catalog.voiceFor('en')!.id, 'tts-en-ljspeech');
      expect(catalog.voiceFor('fr')!.id, 'tts-fr-siwis');
      expect(catalog.voicesFor('de').map((v) => v.id), contains(high.id));
      expect(catalog.models.any((m) => m.id.contains('lessac')), isFalse);
    },
  );

  test('Stimmen sind Archive, die die Plattform entpackt', () {
    for (final m in catalog.ofKind(SpeechModelKind.tts)) {
      expect(m.files.single.archive, ModelArchive.tarBz2);
      expect(m.note, isNotNull);
    }
  });

  test('Download-Größen bleiben im erwarteten Rahmen', () {
    // Guards against swapping in the full-precision models by accident.
    expect(SpeechModelCatalog.whisperBase.sizeBytes, lessThan(200000000));
    expect(SpeechModelCatalog.whisperSmall.sizeBytes, lessThan(400000000));
    expect(SpeechModelCatalog.sileroVad.sizeBytes, lessThan(5000000));
    expect(
      SpeechModelCatalog.whisperBase.files.first.toString(),
      contains('base'),
    );
  });

  test('effectiveSherpaVoice: gewählte, sonst erste geladene (WP66)', () {
    expect(effectiveSherpaVoice(chosen: 'b', available: ['a', 'b']), 'b');
    expect(effectiveSherpaVoice(chosen: 'c', available: ['a', 'b']), 'a');
    expect(effectiveSherpaVoice(chosen: null, available: ['b']), 'b');
    expect(effectiveSherpaVoice(chosen: 'a', available: <String>[]), isNull);
  });

  test('Sprechermodell (WP92a): Apache-2.0, Prüfsumme, Quelle, Hinweis', () {
    final m = SpeechModelCatalog.speakerCamPlus;
    expect(catalog.byId('speaker-campplus'), m);
    expect(catalog.ofKind(SpeechModelKind.speaker), [m]);
    expect(m.license, startsWith('Apache-2.0'));
    expect(m.attribution, contains('3D-Speaker'));
    expect(m.note, contains('Trainingsdaten'));
    expect(m.source, contains('selbst gehasht'));
    expect(m.files.single.sizeBytes, 28281164);
    expect(
      m.files.single.sha256,
      'aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2',
    );
    expect(m.files.single.url, contains('speaker-recongition-models'));
    expect(m.files.single.archive, ModelArchive.none);
    expect(m.sizeBytes, lessThan(40000000));
  });

  test('trainiertes Wake-Modell (WP129): ein Eintrag, Datei, Prüfsumme, '
      'Namensnennung der Trainingsdaten', () {
    final m = SpeechModelCatalog.wakeClassifierWendelin;
    expect(catalog.byId(m.id), same(m));
    expect(catalog.ofKind(SpeechModelKind.wake), contains(m));
    final f = m.files.single;
    // Dateiname und Id nur hier festgelegt: der Aufrufer nimmt die Konstante.
    expect(f.name, SpeechModelCatalog.wakeClassifierFile);
    expect(f.archive, ModelArchive.none);
    expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(f.sizeBytes, inInclusiveRange(100000, 5000000));
    expect(Uri.parse(f.url).scheme, 'https');
    for (final needed in [
      'Thorsten',
      'Multilingual LibriSpeech (Pratap et al., OpenSLR 94), CC-BY 4.0',
      'M-AILABS Speech Dataset, Copyright (c) 2017-2019 M-AILABS',
      'Tatoeba-Mitwirkende, tatoeba.org',
      'FLEURS (Conneau et al.), CC-BY 4.0',
      'Apache-2.0',
    ]) {
      expect(m.attribution, contains(needed));
    }
    // Die Rechte stehen im Eintrag, damit die Lizenzseite sie zeigt.
    expect(m.license, isNotEmpty);
  });
}
