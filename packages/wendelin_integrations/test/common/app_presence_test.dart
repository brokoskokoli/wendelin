import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Port with exactly one defect each; the contract must catch it.
final class _BadPort implements AppPresencePort {
  _BadPort(
    this.installed, {
    this.ignoreCase = false,
    this.prefix = false,
    this.lenient = false,
    this.alwaysTrue = false,
  });

  final Set<String> installed;
  final bool ignoreCase;
  final bool prefix;
  final bool lenient;
  final bool alwaysTrue;

  @override
  Future<bool> isInstalled(String androidPackage) async {
    if (!lenient) checkAndroidPackage(androidPackage);
    if (alwaysTrue) return true;
    if (ignoreCase) {
      return installed.any(
        (p) => p.toLowerCase() == androidPackage.toLowerCase(),
      );
    }
    if (prefix) return installed.any(androidPackage.startsWith);
    return installed.contains(androidPackage);
  }
}

void main() {
  appPresencePortContract(
    (installed) => FakeAppPresencePort(installed: installed),
    name: 'FakeAppPresencePort',
  );

  group('Vertrag erkennt Defekte', () {
    final Matcher fails = throwsA(isA<TestFailure>());
    final cases = [
      (
        AppPresencePortChecks.exact,
        'Groß/klein',
        (Set<String> i) => _BadPort(i, ignoreCase: true),
      ),
      (
        AppPresencePortChecks.exact,
        'Präfix',
        (Set<String> i) => _BadPort(i, prefix: true),
      ),
      (
        AppPresencePortChecks.invalid,
        'nachsichtig',
        (Set<String> i) => _BadPort(i, lenient: true),
      ),
      (
        AppPresencePortChecks.missing,
        'immer true',
        (Set<String> i) => _BadPort(i, alwaysTrue: true),
      ),
    ];
    for (final (check, defect, create) in cases) {
      test('$check: $defect', () async {
        await expectLater(
          appPresencePortContractChecks(create)[check]!(),
          fails,
        );
      });
    }
  });

  test('isValidAndroidPackage', () {
    expect(isValidAndroidPackage('ch.publisheria.bring'), isTrue);
    expect(isValidAndroidPackage('a_b.c1'), isTrue);
    expect(isValidAndroidPackage('single'), isFalse);
    expect(isValidAndroidPackage('a.1b'), isFalse);
    expect(isValidAndroidPackage('a.b-c'), isFalse);
    expect(() => checkAndroidPackage('x'), throwsArgumentError);
  });

  test('Fake: installieren, deinstallieren, Abfragen, Fehler', () async {
    final port = FakeAppPresencePort();
    expect(await port.isInstalled('md.obsidian'), isFalse);
    port.install('md.obsidian');
    expect(await port.isInstalled('md.obsidian'), isTrue);
    port.uninstall('md.obsidian');
    expect(await port.isInstalled('md.obsidian'), isFalse);
    expect(port.queries, ['md.obsidian', 'md.obsidian', 'md.obsidian']);
    port.failNext('isInstalled');
    await expectLater(
      port.isInstalled('md.obsidian'),
      throwsA(isA<PortException>()),
    );
  });
}
