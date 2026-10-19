import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integrations/integration_spec.dart'
    show pausedError;
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
      for (final k in [
        PortErrorKind.rejected,
        PortErrorKind.notFound,
        PortErrorKind.readOnly,
        PortErrorKind.unsupported,
      ])
        (k, 'fehlgeschlagen', 'failed', 'échoué'),
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
      // „unerwartete Antwort“ nur bei failed, nicht bei den anderen Arten.
      final unexpected = kind == PortErrorKind.failed;
      expect(
        reconnectFailureText(de, failure).contains('unerwartete'),
        unexpected,
      );
      expect(
        reconnectFailureText(en, failure).contains('unexpected'),
        unexpected,
      );
      expect(
        reconnectFailureText(fr, failure).contains('inattendue'),
        unexpected,
      );
    }
    expect(
      reconnectFailureText(en, f('bring', PortErrorKind.failed)),
      contains('Bring!'),
    );
    expect(reconnectHint(en, null, 'ok'), 'ok');
  });

  test('Bring!: Fehlschlag nennt den Ausweg über Teilen, Erfolg nicht', () {
    for (final (l, share) in [
      (AppLocalizationsDe(), 'Teilen'),
      (AppLocalizationsEn(), 'Share'),
      (AppLocalizationsFr(), 'Partager'),
    ]) {
      final failure = f('bring', PortErrorKind.unavailable);
      expect(
        bringReconnectHint(l, failure, 'ok'),
        allOf(contains('Bring!'), contains(share)),
      );
      expect(bringReconnectHint(l, null, 'ok'), 'ok');
    }
  });

  test('Fehlerzeile der Kachel: Marker wird in der App-Sprache formuliert', () {
    expect(
      integrationErrorText(AppLocalizationsEn(), 'gtasks', pausedError),
      allOf(contains('Google Tasks'), contains('paused')),
    );
    expect(
      integrationErrorText(AppLocalizationsFr(), 'ha', pausedError),
      allOf(contains('Home Assistant'), contains('en pause')),
    );
    expect(
      integrationErrorText(AppLocalizationsDe(), 'ha', pausedError),
      contains('pausiert'),
    );
    expect(
      integrationErrorText(AppLocalizationsEn(), 'ha', 'Datei neu auswählen'),
      'Datei neu auswählen',
    );
    expect(integrationErrorText(AppLocalizationsEn(), 'ha', null), isNull);
  });
}
