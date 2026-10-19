import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/l10n/gen/app_localizations_en.dart';
import 'package:wendelin/l10n/gen/app_localizations_fr.dart';
import 'package:wendelin/ui/settings/reconnect_text.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  ReconnectFailure f(String service, PortErrorKind kind) =>
      ReconnectFailure(service, kind, 'Deutscher Text für das Modell');

  test('Text je Art und Sprache, nie die deutsche Meldung des Pakets', () {
    final de = AppLocalizationsDe();
    final en = AppLocalizationsEn();
    final fr = AppLocalizationsFr();
    for (final (kind, de_, en_, fr_) in [
      (
        PortErrorKind.permissionDenied,
        'Zugang abgelehnt',
        'access refused',
        'accès refusé',
      ),
      (
        PortErrorKind.unavailable,
        'nicht erreichbar',
        'not reachable',
        'injoignable',
      ),
      (PortErrorKind.failed, 'fehlgeschlagen', 'failed', 'échoué'),
      (PortErrorKind.rejected, 'fehlgeschlagen', 'failed', 'échoué'),
    ]) {
      final failure = f('gtasks', kind);
      expect(
        reconnectFailureText(de, failure),
        allOf(contains('Google Tasks'), contains(de_)),
      );
      expect(
        reconnectFailureText(en, failure),
        allOf(contains('Google Tasks'), contains(en_)),
      );
      expect(
        reconnectFailureText(fr, failure),
        allOf(contains('Google Tasks'), contains(fr_)),
      );
      expect(reconnectFailureText(en, failure), isNot(contains('Deutscher')));
    }
    expect(
      reconnectFailureText(en, f('bring', PortErrorKind.failed)),
      contains('Bring!'),
    );
    expect(reconnectHint(en, null, 'ok'), 'ok');
  });
}
