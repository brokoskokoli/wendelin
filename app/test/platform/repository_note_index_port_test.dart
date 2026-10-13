import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/repository_note_index_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';

void main() {
  noteIndexPortContract(
    () => RepositoryNoteIndexPort(openInMemoryStorage().notes),
    name: 'RepositoryNoteIndexPort',
  );

  test('Obsidian-Suche über den SQLite-Index (Ende zu Ende)', () async {
    final vault = FakeVaultPort(
      files: {
        'Reisen/Malta.md': 'Tauchen in Sliema',
        '.obsidian/app.json': '{}',
      },
    );
    final obsidian = ObsidianIntegration(
      vault,
      RepositoryNoteIndexPort(openInMemoryStorage().notes),
      settings: () => const ObsidianSettings(vaultName: 'V'),
    );
    final search = obsidian.tools.singleWhere(
      (t) => t.name == 'obsidian__search_notes',
    );
    final o = await search.execute(
      {'query': 'sliema'},
      ToolContext(
        sessionId: 's',
        clock: FixedClock(DateTime.utc(2026, 10, 13)),
        locale: 'de-DE',
        timeZone: 'Europe/Berlin',
      ),
    );
    expect(o.isError, isFalse);
    expect(o.text, contains('"path":"Reisen/Malta.md"'));
  });
}
