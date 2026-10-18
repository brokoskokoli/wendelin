import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/settings/mcp/mcp_add_check.dart';
import 'package:wendelin/ui/settings/mcp/mcp_tool_sheet.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

void main() {
  group('mcpAddError (Eingaben von „+ Server“)', () {
    String? error({
      String name = 'Haus',
      String url = 'https://example.org/mcp',
      McpAuthKind auth = McpAuthKind.none,
      String header = '',
    }) => mcpAddError(
      AppLocalizationsDe(),
      name: name,
      urlText: url,
      auth: auth,
      headerName: header,
    );

    test('gültige Eingaben ergeben keinen Fehler', () {
      expect(error(), isNull);
      expect(error(auth: McpAuthKind.headers, header: 'X-Api-Key'), isNull);
    });

    test('Name, Adresse, Platzhalter und Schema werden geprüft', () {
      expect(error(name: ''), 'Bitte einen Namen angeben.');
      expect(
        error(url: 'https://<host>/mcp'),
        'Bitte die Platzhalter in <…> in der Adresse ersetzen.',
      );
      expect(
        error(url: 'example.org/mcp'),
        'Bitte eine vollständige Adresse angeben (https://…).',
      );
      expect(error(url: 'http://example.org/mcp'), contains('Heimnetz'));
    });

    test('Header-Anmeldung braucht den Namen des Headers', () {
      expect(
        error(auth: McpAuthKind.headers, header: '  '),
        'Bitte den Namen des Headers angeben.',
      );
      expect(error(auth: McpAuthKind.bearer, header: ''), isNull);
    });
  });

  group('Tool-Override', () {
    test('mcpWithTool setzt und entfernt Overrides, Standard wird nicht gespeichert', () {
      final config = McpServerConfig(
        id: 's1',
        name: 'Haus',
        slug: 'haus',
        url: Uri.parse('https://example.org/mcp'),
      );
      final off = mcpWithTool(
        config,
        'licht',
        (o) => mcpCopyOverride(o, enabled: false),
      );
      expect(off.toolOverrides['licht']?.enabled, isFalse);
      final back = mcpWithTool(
        off,
        'licht',
        (o) => mcpCopyOverride(o, enabled: true),
      );
      expect(back.toolOverrides, isEmpty);
    });

    test('mcpCopyOverride kann das Risiko auf null setzen', () {
      final strict = mcpCopyOverride(
        const McpToolOverride(),
        risk: () => RiskLevel.external,
      );
      expect(strict.risk, RiskLevel.external);
      expect(mcpCopyOverride(strict, risk: () => null).risk, isNull);
      expect(mcpCopyOverride(strict, autoRun: true).risk, RiskLevel.external);
    });

    test('Auswahl im Tool-Sheet: lesend ohne/mit Nachfrage', () {
      const none = McpToolOverride();
      const strict = McpToolOverride(risk: RiskLevel.external);
      expect(mcpChoiceSelected(RiskLevel.read, none, 0), isTrue);
      expect(mcpChoiceSelected(RiskLevel.read, none, 1), isFalse);
      expect(mcpChoiceSelected(RiskLevel.read, strict, 0), isFalse);
      expect(mcpChoiceSelected(RiskLevel.read, strict, 1), isTrue);
      expect(mcpChoiceSelected(RiskLevel.read, null, 0), isTrue);
    });

    test(
      'Auswahl im Tool-Sheet: schreibend, „ohne Nachfrage“ nur mit autoRun',
      () {
        const auto = McpToolOverride(autoRun: true);
        expect(mcpChoiceSelected(RiskLevel.write, null, 0), isTrue);
        expect(mcpChoiceSelected(RiskLevel.write, null, 1), isFalse);
        expect(mcpChoiceSelected(RiskLevel.write, auto, 0), isFalse);
        expect(mcpChoiceSelected(RiskLevel.write, auto, 1), isTrue);
        expect(mcpChoiceSelected(RiskLevel.external, null, 0), isFalse);
      },
    );
  });
}
