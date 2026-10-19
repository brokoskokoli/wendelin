import 'dart:typed_data';

import '../src/speaker/speaker_embedder.dart';
import '../src/speaker/speaker_match.dart';
import '../src/speaker/speaker_profile.dart';
import '../src/speaker/speaker_profile_store.dart';

/// [SpeakerEmbedder] that looks the embedding up by the first PCM sample:
/// tests build audio with [FakeSpeakerEmbedder.audio] (a key in sample 0)
/// and the embedder answers with `embeddings[key]`.
final class FakeSpeakerEmbedder implements SpeakerEmbedder {
  /// Creates the fake.
  FakeSpeakerEmbedder(this.embeddings);

  /// Embedding per key.
  final List<Float32List> embeddings;

  /// Makes [embed] throw (model missing).
  bool failing = false;

  /// Number of [embed] calls.
  int embedCalls = 0;

  /// Number of [release] calls.
  int releases = 0;

  /// Audio of [seconds] that [embed] maps to `embeddings[key]`.
  static Int16List audio(int key, {double seconds = 2}) {
    final pcm = Int16List((seconds * speakerSampleRate).round());
    if (pcm.isNotEmpty) pcm[0] = key;
    return pcm;
  }

  @override
  Future<Float32List> embed(Int16List pcm) async {
    embedCalls++;
    if (failing) throw StateError('model missing');
    return embeddings[pcm[0]];
  }

  @override
  Future<void> release() async => releases++;
}

/// [SpeakerProfileStore] in memory (stores the JSON form, so the codec is
/// exercised like on the device).
final class InMemorySpeakerProfileStore implements SpeakerProfileStore {
  final _json = <String, Map<String, Object?>>{};

  /// Everything the store holds, as text (for leak checks in tests).
  String get dump => _json.toString();

  /// Whether nothing is stored.
  bool get isEmpty => _json.isEmpty;

  @override
  Future<List<SpeakerProfile>> load() async => [
    for (final j in _json.values) ?SpeakerProfile.fromJson(j),
  ];

  @override
  Future<void> save(SpeakerProfile profile) async =>
      _json[profile.id] = profile.toJson();

  @override
  Future<void> delete(String id) async => _json.remove(id);

  @override
  Future<void> clear() async => _json.clear();
}

/// [SpeakerRecognizer] with a fixed answer.
final class FakeSpeakerRecognizer implements SpeakerRecognizer {
  /// Creates the fake.
  FakeSpeakerRecognizer(this.answer);

  /// Returned by [identify].
  SpeakerMatch answer;

  /// Makes [identify] throw (the pipeline must survive it).
  bool throwing = false;

  /// Lengths of the audio it was asked about.
  final lengths = <int>[];

  @override
  Future<SpeakerMatch> identify(Int16List pcm) async {
    lengths.add(pcm.length);
    if (throwing) throw StateError('boom');
    return answer;
  }
}
