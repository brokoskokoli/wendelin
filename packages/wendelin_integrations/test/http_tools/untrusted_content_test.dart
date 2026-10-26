// WP157 / ADR 0023: „Kann unsichere Inhalte enthalten“ je HTTP-Tool.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'repo_support.dart';
import 'support.dart';

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'neu-${++_n}';
}

void main() {
  test('Standard ist an (fail-closed), im JSON nur wenn abgeschaltet', () {
    final d = testHttpTool();
    expect(d.mayContainUntrustedContent, isTrue);
    expect(d.toJson().containsKey('mayContainUntrustedContent'), isFalse);
    final off = testHttpTool(mayContainUntrustedContent: false);
    expect(off.toJson()['mayContainUntrustedContent'], isFalse);
  });

  test('JSON-Rundreise und copyWith behalten den Haken', () {
    final off = testHttpTool(mayContainUntrustedContent: false);
    final back = HttpToolDefinition.fromJson(
      jsonDecode(jsonEncode(off.toJson())) as Map<String, Object?>,
    );
    expect(back.mayContainUntrustedContent, isFalse);
    expect(back, off);
    expect(back == testHttpTool(), isFalse, reason: 'fließt in == ein');
    expect(off.copyWith().mayContainUntrustedContent, isFalse);
    expect(off.copyWith(mayContainUntrustedContent: true), testHttpTool());
  });

  test('kaputter Wert (kein bool) wird abgelehnt statt als sicher gelesen', () {
    final json =
        jsonDecode(jsonEncode(testHttpTool().toJson())) as Map<String, Object?>;
    json['mayContainUntrustedContent'] = 'nein';
    expect(() => HttpToolDefinition.fromJson(json), throwsFormatException);
  });

  test('Entwurf übernimmt den Haken in die Definition', () {
    final d = HttpToolDraft.empty('d1')
      ..name = 'x'
      ..description = 'y'
      ..url = 'https://api.example.org/a'
      ..mayContainUntrustedContent = false;
    expect(d.toDefinition().mayContainUntrustedContent, isFalse);
    expect(
      HttpToolDraft.empty('d2').mayContainUntrustedContent,
      isTrue,
      reason: 'Standard an',
    );
    expect(
      HttpToolDraft.of(d.toDefinition()).mayContainUntrustedContent,
      isFalse,
    );
  });

  test('HttpTool ist ContentTrustAware und folgt der Definition', () {
    final m = mockRunner((_) async => throw StateError('nicht aufgerufen'));
    final on = HttpToolsIntegration.all([def(name: 'a')], m.runner).first;
    expect(on.tools.single, isA<ContentTrustAware>());
    expect(
      (on.tools.single as ContentTrustAware).mayContainUntrustedContent,
      isTrue,
    );
    final off = HttpToolsIntegration.all([
      def(name: 'b', mayContainUntrustedContent: false),
    ], m.runner).first.tools.single;
    expect((off as ContentTrustAware).mayContainUntrustedContent, isFalse);
    expect(off, isNot(isA<NoNetworkTarget>()), reason: 'Netzziel');
  });

  test('Import setzt den Haken zurück auf an (Datei erklärt sich nicht '
      'für sicher)', () async {
    final repo = HttpToolRepository(
      store: FakeHttpToolStore(),
      secrets: FakeHttpToolSecretVault(),
      ids: _Ids(),
      onInvalid: (_) {},
    );
    addTearDown(repo.dispose);
    final text = jsonEncode(
      exportHttpTools([testHttpTool(mayContainUntrustedContent: false)]),
    );
    final imported = await repo.importJson(text);
    expect(imported.single.mayContainUntrustedContent, isTrue);
  });
}
