import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/repository_memory_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart' as st;

void main() {
  memoryStoreContract(
    () => RepositoryMemoryPort(openInMemoryStorage().memory),
    name: 'RepositoryMemoryPort',
  );

  test('Kategorien werden in beide Richtungen abgebildet', () async {
    final port = RepositoryMemoryPort(openInMemoryStorage().memory);
    for (final c in MemoryCategory.values) {
      final e = await port.save('Eintrag ${c.name}', category: c, source: 's');
      expect(e.category, c);
    }
    expect(
      (await port.list()).map((e) => e.category).toSet(),
      MemoryCategory.values.toSet(),
    );
  });

  test('SensitiveContentException des Repositorys wird rejected', () async {
    final port = RepositoryMemoryPort(_RejectingRepository());
    await expectLater(
      port.save('Harmlos', category: MemoryCategory.fact, source: 's'),
      throwsA(
        isA<PortException>()
            .having((e) => e.kind, 'kind', PortErrorKind.rejected)
            .having((e) => e.message, 'message', contains('Kartennummern')),
      ),
    );
  });

  test('forget eines unbekannten Eintrags ist notFound', () async {
    final port = RepositoryMemoryPort(openInMemoryStorage().memory);
    await expectLater(
      port.forget('weg'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.notFound,
        ),
      ),
    );
  });

  test('zuletzt genutzt ist erst nach einer Suche gesetzt', () async {
    final clock = FixedClock(DateTime(2026, 10, 13, 8));
    final port = RepositoryMemoryPort(openInMemoryStorage(clock: clock).memory);
    final e = await port.save(
      'Taucht gern',
      category: MemoryCategory.preference,
      source: 's',
    );
    expect(e.lastUsedAt, isNull);
    expect((await port.list()).single.lastUsedAt, isNull);
    // Gleiche Uhrzeit wie beim Speichern: trotzdem als genutzt gemeldet.
    expect((await port.search('Taucht')).single.lastUsedAt, isNotNull);
    clock.advance(const Duration(minutes: 1));
    await port.search('Taucht');
    expect((await port.list()).single.lastUsedAt, isNotNull);
  });
}

/// Repository whose own protection rule rejects everything.
final class _RejectingRepository implements st.MemoryRepository {
  @override
  Future<st.MemoryEntry> save(
    String text, {
    required st.MemoryCategory category,
    required String source,
    PrivacyLevel? privacyFloor,
  }) async =>
      throw const st.SensitiveContentException(SensitiveKind.cardNumber);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
