// Die Obsidian-Contract-Suiten erkennen fehlerhafte Implementierungen:
// jede Variante hat genau einen Defekt.
import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

final Matcher _fails = throwsA(isA<TestFailure>());

/// Vault with switchable defects on top of [FakeVaultPort].
final class _BadVault implements VaultPort {
  _BadVault({
    this.stripsBom = false,
    this.createOverwrites = false,
    this.followsDotDot = false,
    this.keepsTime = false,
    Map<String, String>? files,
  }) : inner = FakeVaultPort(files: files);

  final FakeVaultPort inner;
  final bool stripsBom;
  final bool createOverwrites;
  final bool followsDotDot;
  final bool keepsTime;

  String _p(String path) => followsDotDot
      ? path.replaceAll('..', 'dotdot').replaceFirst(RegExp('^[/.]+'), '')
      : path;

  @override
  Future<List<VaultEntry>> list(String folder) => inner.list(_p(folder));

  @override
  Future<String> read(String path) async {
    final t = await inner.read(_p(path));
    return stripsBom && t.startsWith('﻿') ? t.substring(1) : t;
  }

  @override
  Future<void> write(String path, String content) async {
    final before = inner.modified[path];
    await inner.write(_p(path), content);
    if (keepsTime && before != null) inner.modified[path] = before;
  }

  @override
  Future<void> create(String path, String content) => createOverwrites
      ? inner.write(path, content)
      : inner.create(path, content);

  @override
  Future<void> delete(String path) => inner.delete(path);

  @override
  Future<bool> exists(String path) => inner.exists(_p(path));

  @override
  Future<DateTime> modifiedAt(String path) => inner.modifiedAt(path);

  @override
  Future<int> size(String path) => inner.size(path);
}

/// Index with switchable defects on top of [FakeNoteIndex].
final class _BadIndex implements NoteIndexPort {
  _BadIndex({this.ignoresTitle = false, this.appends = false});

  final FakeNoteIndex inner = FakeNoteIndex();
  final bool ignoresTitle;
  final bool appends;

  @override
  Future<void> upsert(
    String path, {
    required String title,
    required String body,
    required DateTime modifiedAt,
  }) {
    final old = inner.notes[path];
    return inner.upsert(
      path,
      title: ignoresTitle ? '' : title,
      body: appends && old != null ? '${old.body} $body' : body,
      modifiedAt: modifiedAt,
    );
  }

  @override
  Future<void> upsertAll(List<IndexedNote> notes) async {
    for (final n in notes) {
      await upsert(
        n.path,
        title: n.title,
        body: n.body,
        modifiedAt: n.modifiedAt,
      );
    }
  }

  @override
  Future<void> remove(String path) => inner.remove(path);

  @override
  Future<List<NoteHit>> search(String query, {int limit = 10}) =>
      inner.search(query, limit: limit);

  @override
  Future<Map<String, DateTime>> knownFiles() => inner.knownFiles();
}

void main() {
  group('vaultPortContract erkennt', () {
    Future<void> fails(_BadVault Function() make, String check) => expectLater(
      vaultPortContractChecks(
        () => (port: make(), reopen: null, dispose: null),
      )[check]!(),
      _fails,
    );

    test(
      'verschluckte BOM',
      () => fails(() => _BadVault(stripsBom: true), VaultPortChecks.exact),
    );
    test(
      'create überschreibt',
      () => fails(
        () => _BadVault(createOverwrites: true),
        VaultPortChecks.createExclusive,
      ),
    );
    test(
      '.. wird umgedeutet statt abgewiesen',
      () => fails(() => _BadVault(followsDotDot: true), VaultPortChecks.unsafe),
    );
    test(
      'modifiedAt bleibt stehen',
      () => fails(() => _BadVault(keepsTime: true), VaultPortChecks.metadata),
    );
    test('nicht persistierende Instanz', () async {
      await expectLater(
        vaultPortContractChecks(
          () => (port: _BadVault(), reopen: _BadVault.new, dispose: null),
        )[VaultPortChecks.persisted]!(),
        _fails,
      );
    });
  });

  group('noteIndexPortContract erkennt', () {
    test('Titel zählt nicht', () async {
      await expectLater(
        noteIndexPortContractChecks(
          () => _BadIndex(ignoresTitle: true),
        )[NoteIndexChecks.titleFirst]!(),
        _fails,
      );
    });
    test('upsert hängt an statt zu ersetzen', () async {
      await expectLater(
        noteIndexPortContractChecks(
          () => _BadIndex(appends: true),
        )[NoteIndexChecks.replace]!(),
        _fails,
      );
    });
    test('korrekte Variante besteht alle Prüfungen', () async {
      for (final check in noteIndexPortContractChecks(_BadIndex.new).values) {
        await check();
      }
    });
  });
}
