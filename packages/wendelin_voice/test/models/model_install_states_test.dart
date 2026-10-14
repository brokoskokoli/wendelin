import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  late FakeSpeechModelService service;
  late ModelInstallStates states;
  late List<SpeechModel> installedEvents;
  late List<String> logs;
  late int changes;
  var serviceFails = false;

  setUp(() {
    service = FakeSpeechModelService();
    installedEvents = [];
    logs = [];
    changes = 0;
    serviceFails = false;
    states = ModelInstallStates(
      catalog: () => SpeechModelCatalog.standard,
      service: () async =>
          serviceFails ? throw StateError('kein Verzeichnis') : service,
      onChanged: (_) => changes++,
      onInstalled: installedEvents.add,
      log: logs.add,
    );
  });

  tearDown(() => states.dispose());

  const base = 'whisper-base';

  test('refresh: installiert, teilweise, fehlend; unbekannt davor', () async {
    expect(states.of(base).phase, ModelPhase.unknown);
    service.installed.add(base);
    service.partial.add('whisper-small');
    await states.refresh();
    expect(states.of(base).phase, ModelPhase.installed);
    expect(states.of('whisper-small').phase, ModelPhase.partial);
    expect(states.of('silero-vad').phase, ModelPhase.absent);
    expect(
      states.states.keys,
      hasLength(SpeechModelCatalog.standard.models.length),
    );
    expect(changes, SpeechModelCatalog.standard.models.length);
  });

  test(
    'refresh ohne Modellverzeichnis: alles unbekannt, Hinweis im Log',
    () async {
      serviceFails = true;
      await states.refresh();
      expect(states.states, isEmpty);
      expect(logs.single, contains('Modellverzeichnis nicht verfügbar'));
      await expectLater(states.refreshKeepingError(base), throwsStateError);
    },
  );

  test(
    'Download: Fortschritt, Entpacken, installiert erst nach install()',
    () async {
      final done = states.download(base);
      expect(states.of(base).phase, ModelPhase.downloading);
      await Future<void>.delayed(Duration.zero);
      service.progress(base, 0.5);
      expect(
        states.of(base),
        const ModelState(ModelPhase.downloading, progress: 0.5),
      );
      service.unpack(base);
      expect(
        states.of(base),
        const ModelState(ModelPhase.unpacking, progress: 1),
      );
      expect(states.of(base).busy, isTrue);
      expect(installedEvents, isEmpty, reason: 'noch nicht installiert');
      service.finish(base);
      await done;
      expect(
        states.of(base),
        const ModelState(ModelPhase.installed, progress: 1),
      );
      expect(installedEvents.single.id, base);
      expect(states.of(base).busy, isFalse);
    },
  );

  test('zweiter Start während des Downloads und unbekanntes Modell tun '
      'nichts', () async {
    final first = states.download(base);
    await Future<void>.delayed(Duration.zero);
    await states.download(base);
    await states.download('gibtsnicht');
    expect(service.running.keys, [base]);
    service.finish(base);
    await first;
  });

  test('Abbruch behält den Rest und meldet keinen Fehler', () async {
    final done = states.download(base);
    await Future<void>.delayed(Duration.zero);
    service.progress(base, 0.3);
    states.cancel(base);
    await done;
    expect(states.of(base), const ModelState(ModelPhase.partial));
    expect(installedEvents, isEmpty);
    expect(states.of(base).error, isNull);
  });

  test('Fehler wird nicht als installiert gemeldet, Text deutsch, Rest '
      'bleibt fortsetzbar', () async {
    final done = states.download(base);
    await Future<void>.delayed(Duration.zero);
    service.fail(
      base,
      const ModelDownloadException(DownloadErrorKind.network, 'Netz weg.'),
      keepPartial: true,
    );
    await done;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final s = states.of(base);
    expect(s.phase, ModelPhase.partial);
    expect(s.error, 'Netz weg.');
    expect(installedEvents, isEmpty);
    // Mit Fehler wird nicht automatisch fortgesetzt.
    await states.resumePartial();
    expect(service.running, isEmpty);
  });

  test('Fehler ohne Rest: fehlend mit Meldung', () async {
    final done = states.download(base);
    await Future<void>.delayed(Duration.zero);
    service.fail(base, StateError('x'));
    await done;
    await Future<void>.delayed(Duration.zero);
    expect(
      states.of(base),
      const ModelState(
        ModelPhase.absent,
        error: 'Der Download ist fehlgeschlagen.',
      ),
    );
  });

  test('resumePartial setzt teilweise Downloads ohne Fehler fort', () async {
    service.partial.add('silero-vad');
    service.installed.add(base);
    await states.resumePartial();
    await Future<void>.delayed(Duration.zero);
    expect(service.running.keys, ['silero-vad'], reason: 'nur der Rest');
    expect(states.of('silero-vad').phase, ModelPhase.downloading);
    service.finish('silero-vad');
    await Future<void>.delayed(Duration.zero);
    expect(states.of('silero-vad').phase, ModelPhase.installed);
  });

  test('delete: entfernt, meldet die Änderung; läuft nicht während '
      'des Downloads', () async {
    service.installed.add(base);
    await states.refresh();
    await states.delete(base);
    expect(service.deleted, [base]);
    expect(states.of(base).phase, ModelPhase.absent);
    expect(installedEvents.single.id, base);

    final done = states.download(base);
    await Future<void>.delayed(Duration.zero);
    await states.delete(base);
    expect(service.deleted, [base], reason: 'läuft noch');
    await states.delete('gibtsnicht');
    service.finish(base);
    await done;
  });

  test('refresh überspringt laufende Downloads', () async {
    final done = states.download(base);
    await Future<void>.delayed(Duration.zero);
    service.installed.add(base);
    await states.refresh();
    expect(states.of(base).phase, ModelPhase.downloading);
    service.finish(base);
    await done;
  });

  test('nach dispose: keine Meldungen mehr, laufender Download wird '
      'abgebrochen', () async {
    final done = states.download(base);
    await Future<void>.delayed(Duration.zero);
    states.dispose();
    final before = changes;
    await done;
    service.installed.add('silero-vad');
    await states.refresh();
    expect(changes, before);
    expect(installedEvents, isEmpty);
    states.cancel('gibtsnicht');
  });

  test('ModelState: Gleichheit, busy, Text', () {
    const a = ModelState(ModelPhase.downloading, progress: 0.5);
    expect(a.busy, isTrue);
    expect(a, const ModelState(ModelPhase.downloading, progress: 0.5));
    expect(a.hashCode, isNot(const ModelState(ModelPhase.absent).hashCode));
    expect(a.toString(), contains('downloading'));
    expect(const ModelState(ModelPhase.partial).busy, isFalse);
  });

  test('downloadErrorText', () {
    expect(
      downloadErrorText(
        const InsufficientSpaceException(
          requiredBytes: 300000000,
          freeBytes: 100000000,
        ),
      ),
      'Zu wenig Speicherplatz: 300 MB nötig, 100 MB frei.',
    );
    expect(
      downloadErrorText(const ArchiveRejected('Unsicherer Pfad')),
      'Unsicherer Pfad',
    );
    expect(
      downloadErrorText(
        const ModelDownloadException(DownloadErrorKind.checksum, 'Prüfsumme'),
      ),
      'Prüfsumme',
    );
    expect(
      downloadErrorText(StateError('x')),
      'Der Download ist fehlgeschlagen.',
    );
  });
}
