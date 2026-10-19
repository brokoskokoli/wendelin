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
}
