import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  const catalog = SpeechModelCatalog.standard;

  test('enthält Whisper base/small, Silero VAD und Stimmen de/fr/en', () {
    expect(catalog.ofKind(SpeechModelKind.stt).map((m) => m.id), [
      'whisper-base',
      'whisper-small',
    ]);
    for (final m in catalog.ofKind(SpeechModelKind.stt)) {
      expect(m.languages, containsAll(['de', 'fr', 'en']));
    }
    expect(catalog.ofKind(SpeechModelKind.vad).single.id, 'silero-vad');
    expect(catalog.voiceFor('de-DE')?.id, 'tts-de-thorsten');
    expect(catalog.voiceFor('fr')?.id, 'tts-fr-siwis');
    expect(catalog.voiceFor('en_US')?.id, 'tts-en-amy');
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
      for (final f in m.files) {
        expect(f.url, matches(RegExp(r'/resolve/[0-9a-f]{40}/')));
        expect(f.archive, ModelArchive.none);
      }
    }
  });

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
}
