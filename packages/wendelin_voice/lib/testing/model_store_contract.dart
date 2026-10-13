import 'dart:async';

import 'package:test/test.dart';

import '../src/models/model_store.dart';

/// Contract for every [ModelStore]. [create] returns an empty store.
void modelStoreContract(
  FutureOr<ModelStore> Function() create, {
  String name = 'ModelStore',
}) {
  const m = 'contract-model';
  const f = 'file.bin';

  Future<List<int>> partial(ModelStore s) async => [
    for (final chunk in await s.readPartial(m, f).toList()) ...chunk,
  ];

  group('$name erfüllt den ModelStore-Vertrag', () {
    test('leerer Store: nichts vorhanden, Teil-Länge 0', () async {
      final s = await create();
      expect(await s.exists(m, f), isFalse);
      expect(await s.partialLength(m, f), 0);
      expect(await partial(s), isEmpty);
    });

    test('append hängt an, readPartial liefert in Reihenfolge', () async {
      final s = await create();
      await s.append(m, f, [1, 2, 3]);
      await s.append(m, f, [4, 5]);
      expect(await s.partialLength(m, f), 5);
      expect(await partial(s), [1, 2, 3, 4, 5]);
      expect(await s.exists(m, f), isFalse);
      await s.deleteModel(m);
    });

    test('truncate leert den Teil-Download', () async {
      final s = await create();
      await s.append(m, f, [1, 2, 3]);
      await s.truncate(m, f);
      expect(await s.partialLength(m, f), 0);
      await s.deleteModel(m);
    });

    test('commit macht die Datei sichtbar und entfernt den Teil', () async {
      final s = await create();
      await s.append(m, f, [9, 9]);
      await s.commit(m, f);
      expect(await s.exists(m, f), isTrue);
      expect(await s.partialLength(m, f), 0);
      // A second download replaces the final file.
      await s.append(m, f, [7]);
      await s.commit(m, f);
      expect(await s.exists(m, f), isTrue);
      await s.deleteModel(m);
      expect(await s.exists(m, f), isFalse);
    });

    test('commit ohne Teil-Download wirft StateError', () async {
      final s = await create();
      await expectLater(s.commit(m, f), throwsStateError);
    });

    test('Löschen fehlender Dateien ist wirkungslos', () async {
      final s = await create();
      await s.deletePartial(m, f);
      await s.deleteModel(m);
      await s.append(m, f, [1]);
      await s.deletePartial(m, f);
      expect(await s.partialLength(m, f), 0);
    });
  });
}
