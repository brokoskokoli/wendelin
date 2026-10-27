// WP155: Warten auf die Schreibwarteschlangen (deleteDevAudio, clearDevArchive)
// darf nicht an der Zone hängen, in der die Warteschlange zuerst angelegt
// wurde. Eigene Datei: die Warteschlange entsteht je Isolate nur einmal.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/dev_archive.dart';
import 'package:wendelin/voice/dev_audio.dart';

void main() {
  test('Idle-Wartezeit endet auch in einer anderen Zone als der ersten', () {
    devAudioDirectory = () async => null;
    // Erste Berührung in einer Zone, die danach nie mehr läuft.
    fakeAsync((a) {
      deleteDevAudio();
      clearDevArchive();
      a.flushMicrotasks();
    });
    var audio = false;
    var archive = false;
    fakeAsync((b) {
      deleteDevAudio().then((_) => audio = true);
      clearDevArchive().then((_) => archive = true);
      b.flushMicrotasks();
    });
    expect(audio, isTrue, reason: 'deleteDevAudio hängt');
    expect(archive, isTrue, reason: 'clearDevArchive hängt');
  });
}
