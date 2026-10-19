import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/sherpa_speaker.dart';
import '../voice/speaker/speaker_storage.dart';
import 'core_providers.dart';
import 'voice_providers.dart';

// Wiring of the speaker recognition (WP92a). Without the switch, the model
// or profiles nothing is loaded and nothing is computed.

/// Encrypted profile store (embeddings only).
final speakerProfileStoreProvider = Provider<SpeakerProfileStore>(
  (ref) => SecretSpeakerProfileStore(ref.watch(secretStoreProvider)),
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
  }) async {
    final identifier = ref.read(speakerIdentifierProvider);
    final result = await identifier.enroll(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      samples: samples,
    );
    state = AsyncData(await identifier.profiles());
    return result;
  }

  /// Deletes the person [id].
  Future<void> remove(String id) async {
    final identifier = ref.read(speakerIdentifierProvider);
    await identifier.remove(id);
    state = AsyncData(await identifier.profiles());
  }

  /// Deletes everyone („Alles löschen“).
  Future<void> removeAll() async {
    await ref.read(speakerIdentifierProvider).removeAll();
    state = const AsyncData([]);
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
