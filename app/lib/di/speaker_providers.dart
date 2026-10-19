import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/sherpa_speaker.dart';
import '../voice/speaker/person_scope.dart';
import '../voice/speaker/person_storage.dart';
import '../voice/speaker/speaker_storage.dart';
import 'core_providers.dart';
import 'voice_providers.dart';

// Wiring of the speaker recognition (WP92a). Without the switch, the model
// or profiles nothing is loaded and nothing is computed.

/// Encrypted profile store (embeddings only).
final speakerProfileStoreProvider = Provider<SpeakerProfileStore>(
  (ref) => SecretSpeakerProfileStore(ref.watch(secretStoreProvider)),
);

/// Encrypted per-person settings (address, memory, agent; WP92b).
final personSettingsStoreProvider = Provider<PersonSettingsStore>(
  (ref) => SecretPersonSettingsStore(ref.watch(secretStoreProvider)),
);

/// Turns the id of a recognized person into its request scope.
final personScopeResolverProvider = Provider<PersonScopeResolver>(
  (ref) => PersonScopeResolver(
    profiles: ref.watch(speakerProfileStoreProvider),
    settings: ref.watch(personSettingsStoreProvider),
  ),
);

/// Embedding model; loads lazily on first use (tests replace it).
final speakerEmbedderProvider = Provider<SpeakerEmbedder>((ref) {
  final embedder = _LazyEmbedder(ref);
  ref.onDispose(() => unawaited(embedder.release()));
  return embedder;
});

/// The one identifier (enrollment, recognition, release).
final speakerIdentifierProvider = Provider<SpeakerIdentifier>(
  (ref) => SpeakerIdentifier(
    embedder: ref.watch(speakerEmbedderProvider),
    store: ref.watch(speakerProfileStoreProvider),
  ),
);

/// Whether the switch is on (only this bool is watched by the voice wiring).
final speakerRecognitionEnabledProvider = Provider<bool>(
  (ref) => ref.watch(voiceSettingsProvider).value?.speakerRecognition ?? false,
);

/// The recognizer for the pipeline; `null` while the switch is off.
final speakerRecognizerProvider = Provider<SpeakerRecognizer?>((ref) {
  final identifier = ref.watch(speakerIdentifierProvider);
  if (ref.watch(speakerRecognitionEnabledProvider)) return identifier;
  // Switched off: free the model (a no-op when it was never loaded).
  unawaited(identifier.release());
  return null;
});

/// The enrolled persons.
final speakerProfilesProvider =
    AsyncNotifierProvider<SpeakerProfilesNotifier, List<SpeakerProfile>>(
      SpeakerProfilesNotifier.new,
    );

/// Enrolled persons with enroll and delete (embeddings go with them).
final class SpeakerProfilesNotifier
    extends AsyncNotifier<List<SpeakerProfile>> {
  @override
  Future<List<SpeakerProfile>> build() =>
      ref.read(speakerIdentifierProvider).profiles();

  /// Enrolls [name] from the recordings [samples].
  Future<SpeakerEnrollResult> enroll({
    required String name,
    required List<Int16List> samples,
    String? id,
  }) async {
    final identifier = ref.read(speakerIdentifierProvider);
    final result = await identifier.enroll(
      id: id ?? 'p${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      samples: samples,
    );
    state = AsyncData(await identifier.profiles());
    return result;
  }

  /// Deletes the person [id]: embeddings, settings and the entries of the
  /// person's own memory namespace. The default memory stays untouched, also
  /// when the person used it.
  Future<void> remove(String id) async {
    final identifier = ref.read(speakerIdentifierProvider);
    final storage = ref.read(storageProvider);
    // Data first, the voice last: if one step fails the person stays
    // enrolled and the deletion can be repeated.
    await storage.memory.deleteOwner(PersonSettings.ownerOf(id));
    await storage.conversations.deletePersonSessions(person: id);
    await ref.read(personSettingsStoreProvider).delete(id);
    await identifier.remove(id);
    ref.invalidate(personSettingsProvider);
    state = AsyncData(await identifier.profiles());
  }

  /// Deletes everyone („Alles löschen“), also their memory namespaces and
  /// conversations (also those of persons that are no longer enrolled).
  Future<void> removeAll() async {
    final identifier = ref.read(speakerIdentifierProvider);
    final storage = ref.read(storageProvider);
    await storage.memory.deleteAllPersons();
    await storage.conversations.deletePersonSessions();
    await ref.read(personSettingsStoreProvider).clear();
    await identifier.removeAll();
    ref.invalidate(personSettingsProvider);
    state = const AsyncData([]);
  }
}

/// The settings of the enrolled persons by id; a person without an entry has
/// the defaults (`PersonSettings(personId: …)`).
final personSettingsProvider =
    AsyncNotifierProvider<PersonSettingsNotifier, Map<String, PersonSettings>>(
      PersonSettingsNotifier.new,
    );

/// Reads and changes the per-person settings.
final class PersonSettingsNotifier
    extends AsyncNotifier<Map<String, PersonSettings>> {
  @override
  Future<Map<String, PersonSettings>> build() =>
      ref.read(personSettingsStoreProvider).load();

  /// Saves [settings].
  Future<void> change(PersonSettings settings) async {
    await ref.read(personSettingsStoreProvider).save(settings);
    state = AsyncData({...?state.value, settings.personId: settings});
  }
}

final class _LazyEmbedder implements SpeakerEmbedder {
  _LazyEmbedder(this._ref);

  final Ref _ref;
  SherpaSpeakerEmbedder? _inner;

  @override
  Future<Float32List> embed(Int16List pcm) async {
    var inner = _inner;
    if (inner == null) {
      final service = await _ref.read(speechModelServiceProvider.future);
      final model = SpeechModelCatalog.speakerCamPlus;
      inner = _inner = SherpaSpeakerEmbedder(
        model: model,
        directory: service.directoryOf(model).path,
      );
    }
    return inner.embed(pcm);
  }

  @override
  Future<void> release() async {
    final inner = _inner;
    _inner = null;
    await inner?.release();
  }
}
