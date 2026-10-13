// Review WP16: optimistische Sperre beim Schreiben der Listen und die
// erweiterte Akzent-Faltung des unscharfen Abgleichs.
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/common/file_queue.dart';
import 'package:wendelin_integrations/src/common/matching.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeListFilePort port;
  late ListsIntegration lists;

  Future<ToolOutcome> run(String name, Map<String, Object?> args) =>
      lists.tools.singleWhere((t) => t.name == name).execute(args, ctx());

  setUp(() {
    port = FakeListFilePort(files: {'e.md': '- [ ] Milch\n'});
    lists = ListsIntegration(
      port,
      definitions: () => [
        ListDefinition(id: 'e', name: 'Einkaufen', target: 'e.md'),
      ],
    );
  });

  test(
    'fremde Änderung zwischen Lesen und Schreiben: erneut angewandt',
    () async {
      var once = true;
      port.onRead = (h) {
        if (once) {
          once = false;
          port.files[h] = '- [ ] Milch\n- [ ] Brot\n';
        }
      };
      final o = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Eier'],
      });
      expect(o.isError, isFalse, reason: o.text);
      expect(port.files['e.md'], '- [ ] Milch\n- [ ] Brot\n- [ ] Eier\n');
    },
  );

  test(
    'Datei entsteht zwischen Lesen und Schreiben: nicht überschrieben',
    () async {
      port.files.clear();
      var once = true;
      // Erstes exists (beim Laden) sagt „fehlt“, danach legt Sync sie an.
      lists = ListsIntegration(
        _CreatingPort(port, () {
          if (once) {
            once = false;
            port.files['e.md'] = '- [ ] von Sync\n';
          }
        }),
        definitions: () => [
          ListDefinition(id: 'e', name: 'Einkaufen', target: 'e.md'),
        ],
      );
      final o = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Eier'],
      });
      expect(o.isError, isFalse, reason: o.text);
      expect(port.files['e.md'], '- [ ] von Sync\n- [ ] Eier\n');
    },
  );

  test('ständige Änderung: Fehler, nichts überschrieben', () async {
    var n = 0;
    port.onRead = (h) => port.files[h] = '- [ ] Milch ${n++}\n';
    final o = await run('lists__add_items', {
      'list': 'Einkaufen',
      'items': ['Eier'],
    });
    expect(o.isError, isTrue);
    expect(o.text, contains('von außen geändert'));
    expect(port.files['e.md'], isNot(contains('Eier')));
    expect(FileQueue.pending, 0);
  });

  test('Undo nutzt die Sperre ebenfalls', () async {
    final o = await run('lists__add_items', {
      'list': 'Einkaufen',
      'items': ['Eier'],
    });
    var once = true;
    port.onRead = (h) {
      if (once) {
        once = false;
        port.files[h] = '# Kopf\n${port.files[h]}';
      }
    };
    await o.undo!();
    expect(port.files['e.md'], '# Kopf\n- [ ] Milch\n');
  });

  test('Akzente werden gefaltet (Verhaltensänderung WP16)', () {
    expect(normalizeText('Zoë Íñigo Ça'), 'zoe inigo ca');
    expect(matchScore('Creme brulee', 'Crème brûlée'), 3);
    expect(matchScore('Noel', 'Noël'), 3);
  });
}

/// Port whose first `exists` reports the file missing and then lets
/// [onFirstExists] create it (Sync creates the file meanwhile).
final class _CreatingPort implements ListFilePort {
  _CreatingPort(this.inner, this.onFirstExists);

  final FakeListFilePort inner;
  final void Function() onFirstExists;
  var _first = true;

  @override
  Future<bool> exists(String handle) async {
    final r = await inner.exists(handle);
    if (_first) {
      _first = false;
      onFirstExists();
    }
    return r;
  }

  @override
  Future<String> read(String handle) => inner.read(handle);

  @override
  Future<void> write(String handle, String content) =>
      inner.write(handle, content);
}
