import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/wake_feature_chain.dart';

/// Counts calls; mel gives `n / 160 - 3` frames of value `call index`.
final class FakeRunner implements WakeModelRunner {
  final melInputs = <int>[];
  final embedInputs = <Float32List>[];
  var closed = false;

  @override
  Float32List mel(Float32List samples) {
    melInputs.add(samples.length);
    final frames = samples.length ~/ 160 - 3;
    return Float32List(frames * 32)..fillRange(0, frames * 32, 10.0);
  }

  @override
  Float32List embed(Float32List frames) {
    embedInputs.add(frames);
    return Float32List(96)..fillRange(0, 96, embedInputs.length.toDouble());
  }

  @override
  void close() => closed = true;
}

Int16List pcm(int n, [int v = 1]) => Int16List(n)..fillRange(0, n, v);

void main() {
  test(
    'Chunks à 1 280 Samples mit 480 Samples Kontext ergeben 8 Mel-Frames',
    () {
      final r = FakeRunner();
      WakeFeatureChain(r).accept(pcm(1280 * 3));
      expect(r.melInputs, [1760, 1760, 1760]);
    },
  );

  test('erstes Fenster nach 25 Chunks, danach eins je Chunk', () {
    final r = FakeRunner();
    final chain = WakeFeatureChain(r);
    final ends = <int>[];
    for (var i = 0; i < 27; i++) {
      ends.addAll(chain.accept(pcm(1280)).map((w) => w.endSample));
    }
    // 10 Chunks bis 76 Mel-Frames, 16 Embeddings für das Fenster.
    expect(ends, [1280 * 25, 1280 * 26, 1280 * 27]);
    expect(r.embedInputs, hasLength(18));
  });

  test('Skalierung x/10+2 und Fensterinhalt (16 × 96)', () {
    final r = FakeRunner();
    final chain = WakeFeatureChain(r);
    final windows = chain.accept(pcm(1280 * 25));
    expect(windows, hasLength(1));
    expect(r.embedInputs.first.every((v) => v == 3.0), isTrue); // 10/10+2
    expect(r.embedInputs.first, hasLength(76 * 32));
    final w = windows.single.embedding;
    expect(w, hasLength(1536));
    expect(w.first, 1); // ältestes Embedding zuerst
    expect(w.last, 16);
  });

  test('beliebige Framegrößen ergeben dasselbe wie ganze Chunks', () {
    Int16List signal() =>
        Int16List.fromList([for (var i = 0; i < 1280 * 26; i++) i % 100]);
    final a = FakeRunner(), b = FakeRunner();
    final whole = WakeFeatureChain(a).accept(signal());
    final chain = WakeFeatureChain(b);
    final parts = <int>[];
    final s = signal();
    for (var i = 0; i < s.length; i += 333) {
      parts.addAll(
        chain
            .accept(Int16List.sublistView(s, i, (i + 333).clamp(0, s.length)))
            .map((w) => w.endSample),
      );
    }
    expect(parts, whole.map((w) => w.endSample));
    expect(b.melInputs, a.melInputs);
  });

  test(
    'Kontext: der zweite Chunk sieht die letzten 480 Samples des ersten',
    () {
      final inputs = <Float32List>[];
      final chain = WakeFeatureChain(_Capture(inputs));
      chain.accept(Int16List.fromList([for (var i = 0; i < 2560; i++) i]));
      expect(inputs[0].sublist(0, 480).every((v) => v == 0), isTrue);
      expect(inputs[1][0], 800); // Sample 800 = 1280 - 480
      expect(inputs[1][480], 1280);
    },
  );

  test('reset beginnt einen neuen Strom', () {
    final r = FakeRunner();
    final chain = WakeFeatureChain(r);
    chain.accept(pcm(1280 * 25));
    chain.reset();
    expect(chain.accept(pcm(1280 * 24)), isEmpty);
    expect(chain.accept(pcm(1280)).single.endSample, 1280 * 25);
  });

  test(
    'Extractor: offen, öffnet nur einmal, close gibt die Modelle frei',
    () async {
      final r = FakeRunner();
      var loads = 0;
      final x = ChainWakeFeatureExtractor(() async {
        loads++;
        return r;
      });
      expect(() => x.accept(pcm(10)), throwsStateError);
      await x.open();
      await x.open();
      expect(loads, 1);
      expect(x.featureVersion, wakeFeatureVersion);
      expect(await x.accept(pcm(1280 * 25)), hasLength(1));
      await x.close();
      expect(r.closed, isTrue);
    },
  );
}

final class _Capture implements WakeModelRunner {
  _Capture(this.inputs);
  final List<Float32List> inputs;

  @override
  Float32List mel(Float32List samples) {
    inputs.add(Float32List.fromList(samples));
    return Float32List(8 * 32);
  }

  @override
  Float32List embed(Float32List frames) => Float32List(96);

  @override
  void close() {}
}
