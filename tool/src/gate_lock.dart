// Rechnerweiter Gate-Semaphor (WP97): höchstens [GateSlots.max] Gate-Läufe
// gleichzeitig. Jeder Lauf belegt eine Slot-Datei `slot-<n>.lock` mit seiner
// PID unter `~/.cache/wendelin-gate/slots/`. Slots toter Prozesse werden
// aufgeräumt. Fail-open: ist der Ordner nicht nutzbar, läuft das Gate ohne
// Sperre weiter.
import 'dart:async';
import 'dart:io';

/// Belegter Slot; [release] gibt ihn frei (mehrfach aufrufbar).
final class SlotLease {
  /// Erstellt eine Belegung für [file] (`null` = ohne Sperre).
  SlotLease(this.file, [this.ownPid]);

  /// Slot-Datei.
  final File? file;

  /// PID des Besitzers; [release] löscht nur, solange die Datei sie trägt.
  final int? ownPid;

  /// Gibt den Slot frei.
  void release() {
    try {
      final f = file;
      if (f == null) return;
      if (ownPid != null && f.readAsStringSync().trim() != '$ownPid') return;
      f.deleteSync();
    } on Object {
      // schon weg
    }
  }
}

/// Zählende Sperre über Dateien.
final class GateSlots {
  /// Erstellt den Semaphor. Alles Zeitabhängige ist austauschbar.
  GateSlots({
    required this.dir,
    this.max = 2,
    int? ownPid,
    bool Function(int pid)? isAlive,
    this.sleep = _sleep,
    this.poll = const Duration(seconds: 2),
    void Function(String)? log,
    this.staleEmpty = const Duration(seconds: 10),
    this.guardStale = const Duration(seconds: 30),
  }) : ownPid = ownPid ?? pid,
       isAlive = isAlive ?? _isAlive,
       log = log ?? stderr.writeln;

  /// Ordner der Slot-Dateien.
  final Directory dir;

  /// Höchstzahl gleichzeitiger Läufe.
  final int max;

  /// PID dieses Laufs.
  final int ownPid;

  /// Prüft, ob ein Prozess lebt.
  final bool Function(int pid) isAlive;

  /// Wartefunktion.
  final Future<void> Function(Duration) sleep;

  /// Abstand zwischen zwei Versuchen.
  final Duration poll;

  /// Meldungen (Wartehinweis).
  final void Function(String) log;

  /// Eine leere Slot-Datei gilt nach dieser Zeit als verwaist.
  final Duration staleEmpty;

  /// Ein Aufräum-Wächter gilt nach dieser Zeit als verwaist.
  final Duration guardStale;

  /// Belegt einen Slot; wartet mit einer Meldung, bis einer frei ist.
  Future<SlotLease> acquire() async {
    try {
      dir.createSync(recursive: true);
    } on Object catch (e) {
      log('Gate-Semaphor nicht verfügbar ($e), läuft ohne Sperre.');
      return SlotLease(null);
    }
    var told = false;
    while (true) {
      final lease = _tryAcquire();
      if (lease != null) return lease;
      if (!told) {
        told = true;
        log(
          'Gate wartet: $max Läufe aktiv (${_holders().join(', ')}); '
          'weitere Läufe warten, bis ein Slot frei wird.',
        );
      }
      await sleep(poll);
    }
  }

  SlotLease? _tryAcquire() {
    for (var i = 0; i < max; i++) {
      final f = File('${dir.path}/slot-$i.lock');
      try {
        f.createSync(exclusive: true);
        f.writeAsStringSync('$ownPid');
        return SlotLease(f, ownPid);
      } on FileSystemException {
        _reapIfDead(f);
        // Nach dem Aufräumen gleich noch einmal versuchen.
        try {
          f.createSync(exclusive: true);
          f.writeAsStringSync('$ownPid');
          return SlotLease(f, ownPid);
        } on FileSystemException {
          continue;
        }
      }
    }
    return null;
  }

  /// Räumt einen toten Slot auf. Unter einer Wächterdatei je Slot (nur ein
  /// Aufräumer gleichzeitig) und mit erneutem Lesen vor dem Löschen: Hat
  /// inzwischen ein anderer Lauf den Slot übernommen, bleibt er unberührt.
  void _reapIfDead(File f) {
    final guard = File('${f.path}.reap');
    try {
      try {
        guard.createSync(exclusive: true);
      } on FileSystemException {
        // Wächter eines abgestürzten Aufräumers nach kurzer Zeit verwerfen.
        if (DateTime.now().difference(guard.lastModifiedSync()) > guardStale) {
          guard.deleteSync();
        }
        return;
      }
      try {
        final text = f.readAsStringSync().trim();
        final p = int.tryParse(text);
        final dead = p == null
            ? DateTime.now().difference(f.lastModifiedSync()) > staleEmpty
            : !isAlive(p);
        if (dead && f.readAsStringSync().trim() == text) f.deleteSync();
      } finally {
        guard.deleteSync();
      }
    } on Object {
      // Nicht lesbar: Slot gilt als belegt.
    }
  }

  List<String> _holders() {
    final out = <String>[];
    try {
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.lock')) {
          out.add('PID ${f.readAsStringSync().trim()}');
        }
      }
    } on Object {
      // nur Anzeige
    }
    return out;
  }
}

Future<void> _sleep(Duration d) => Future<void>.delayed(d);

bool _isAlive(int pid) {
  try {
    return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
  } on Object {
    return true;
  }
}

/// Slot-Ordner `~/.cache/wendelin-gate/slots`; `null`, wenn der Semaphor
/// aus ist (`CI=true`, `WENDELIN_GATE_SLOTS=0`, kein HOME).
GateSlots? gateSlotsFromEnvironment(Map<String, String> env) {
  final home = env['HOME'] ?? '';
  if (env['CI'] == 'true' ||
      env['WENDELIN_GATE_SLOTS'] == '0' ||
      home.isEmpty) {
    return null;
  }
  final max = int.tryParse(env['WENDELIN_GATE_MAX_RUNS'] ?? '') ?? 2;
  return GateSlots(
    dir: Directory('$home/.cache/wendelin-gate/slots'),
    max: max < 1 ? 1 : max,
  );
}

/// Führt [body] mit einem belegten Slot aus ([slots] `null` = ohne Sperre).
/// Der Slot wird in jedem Fall freigegeben, auch bei einer Ausnahme und bei
/// SIGINT/SIGTERM (Ausstieg mit 130 bzw. 143).
Future<void> withGateSlot(
  GateSlots? slots,
  Future<void> Function() body,
) async {
  final lease = await slots?.acquire();
  final subs = <StreamSubscription<ProcessSignal>>[];
  if (lease != null) {
    for (final (sig, code) in [
      (ProcessSignal.sigint, 130),
      (ProcessSignal.sigterm, 143),
    ]) {
      try {
        subs.add(
          sig.watch().listen((_) {
            lease.release();
            exit(code);
          }),
        );
      } on Object {
        // Signal auf dieser Plattform nicht verfügbar.
      }
    }
  }
  try {
    await body();
  } finally {
    lease?.release();
    for (final s in subs) {
      await s.cancel();
    }
  }
}
