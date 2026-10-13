import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart' show foldFlat;
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'preferences.dart';
import 'providers.dart';

/// Names for the correction after speech recognition (WP33, B6): the
/// assistant name, the titles of the indexed notes and the list names.
///
/// Privacy: the names stay on the device. They live in memory only, are
/// never logged and are not part of the audit log (it keeps the text that
/// went to the model, as before). Only Wendelin's own speech input is
/// corrected, never the system recognizer for other apps (ADR 0008).
final class VocabularySource {
  /// Creates the source.
  VocabularySource({
    required this.notePaths,
    required this.listNames,
    this.assistantName = 'Wendelin',
  });

  /// Paths of the indexed notes (the index follows the vault).
  final Future<Iterable<String>> Function() notePaths;

  /// Names and aliases of the user's lists.
  final Iterable<String> Function() listNames;

  /// Name of the assistant.
  final String assistantName;

  List<String>? _names;
  Vocabulary _vocabulary = Vocabulary.empty;

  /// The vocabulary for the current index and lists; rebuilt only when the
  /// names changed. If the index cannot be read, the last vocabulary stays
  /// (the error is reported without names).
  Future<Vocabulary> current() async {
    final Iterable<String> paths;
    try {
      paths = await notePaths();
    } on Object catch (e) {
      debugPrint('Vokabular: Notizindex nicht lesbar (${e.runtimeType})');
      return _vocabulary;
    }
    final names = [
      for (final p in paths.toList()..sort()) VaultPath.title(p),
      ...listNames(),
    ];
    if (listEquals(names, _names)) return _vocabulary;
    _names = names;
    return _vocabulary = Vocabulary(names, names: [assistantName]);
  }
}

/// [VocabularySource] on the note index and the list settings.
final vocabularySourceProvider = Provider<VocabularySource>(
  (ref) => VocabularySource(
    notePaths: () async =>
        (await ref.read(storageProvider).notes.knownFiles()).keys,
    listNames: () => [
      for (final l in ref.read(listDefinitionsProvider)) ...[
        l.name,
        ...l.aliases,
      ],
    ],
  ),
);

/// Note titles the speech correction put into the last spoken request
/// (WP33, B8). Lives in memory only. A write to such a note is asked back
/// once ([take] consumes the title), because the user never said the exact
/// name; the assistant name and list names are not tracked.
final class CorrectedTitles {
  final _titles = <String>{};

  /// Replaces the titles with those of the last transcription.
  void record(Iterable<VocabularyTerm> terms) {
    _titles
      ..clear()
      ..addAll([
        for (final t in terms)
          if (!t.name) t.flat,
      ]);
  }

  /// Whether the title of the note [path] came from the correction; removes
  /// it, so the next write after the question goes through.
  bool take(String path) => _titles.remove(foldFlat(VaultPath.title(path)));
}

/// [CorrectedTitles] shared by the speech input and the Obsidian tools.
final correctedTitlesProvider = Provider<CorrectedTitles>(
  (ref) => CorrectedTitles(),
);
