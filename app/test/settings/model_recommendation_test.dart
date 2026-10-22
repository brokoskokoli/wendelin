// WP128: recommended models in the model step (badge, reason, order,
// preselection) for a new provider and for switching the model of an
// existing one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/provider_setup/model_step.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../di/provider_setup_test.dart' show RecordingFactory;
import '../support/test_env.dart';
import '../ui/helpers.dart';

const _opus = ModelInfo(id: 'claude-opus-5-5', displayName: 'Claude Opus 5.5');
const _sonnet = ModelInfo(
  id: 'claude-sonnet-5-5',
  displayName: 'Claude Sonnet 5.5',
);
const _haiku = ModelInfo(
  id: 'claude-haiku-5-5',
  displayName: 'Claude Haiku 5.5',
);

Future<TestEnv> _open(
  WidgetTester tester,
  List<ModelInfo> models, {
  ProviderProfile? existing,
}) async {
  final env = TestEnv(
    storedProfiles: true,
    llmFactory: RecordingFactory(models: models).call,
  );
  setView(tester, screenSize);
  await tester.pumpWidget(
    env.app(
      home: RepaintBoundary(
        key: goldenKey,
        child: ProviderSetupScreen(existing: existing),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (existing == null) {
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.byKey(const ValueKey('apiKey')),
    'testschluessel',
  );
  await tester.tap(find.text('Verbindung testen'));
  await tester.pumpAndSettle();
  return env;
}

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!.text;

void main() {
  const rec = ModelRecommendation(
    modelId: 'b',
    hits: 5,
    runs: 6,
    p50Seconds: 1.5,
    measured: '2026-10-20',
  );
  const a = ModelInfo(id: 'a', displayName: 'a');
  const b = ModelInfo(id: 'b', displayName: 'b');
  const c = ModelInfo(id: 'c', displayName: 'c');

  test('orderModels: empfohlene zuerst, nichts geht verloren', () {
    expect(orderModels([a, b, c], [rec]), [b, a, c]);
    expect(orderModels([a, c], [rec]), [a, c]);
    expect(orderModels([a, b], const []), [a, b]);
  });

  test('preselectModel: Auswahl bleibt, sonst empfohlene, sonst erste', () {
    expect(preselectModel('a', [a, b], [rec]), isNull);
    expect(preselectModel('x', [a, b], [rec]), 'b');
    expect(preselectModel('x', [a, c], [rec]), 'a');
    expect(preselectModel('x', const [], [rec]), isNull);
  });

  testWidgets('neuer Provider: Plakette, Begründung, empfohlene oben, '
      'vorausgewählt', (tester) async {
    await _open(tester, const [_opus, _sonnet, _haiku]);
    expect(find.text('Empfohlen'), findsOneWidget);
    expect(
      find.textContaining('58 von 58 Testläufen richtig, typisch 1,9 s'),
      findsOneWidget,
    );
    expect(find.textContaining('gemessen am 2026-10-20'), findsOneWidget);
    final haiku = tester.getTopLeft(find.text('Claude Haiku 5.5')).dy;
    expect(haiku, lessThan(tester.getTopLeft(find.text('Claude Opus 5.5')).dy));
    expect(_field(tester), 'claude-haiku-5-5');
  });

  testWidgets('Golden Empfehlung im Modellschritt', tags: ['golden'], (
    tester,
  ) async {
    await _open(tester, const [_opus, _sonnet, _haiku]);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/modell_empfohlen.png'),
    );
  });

  testWidgets('Modellwechsel eines bestehenden Providers: Auswahl bleibt, '
      'Empfehlung steht oben', (tester) async {
    final profile = ProviderProfile(
      id: 'claude',
      name: 'Claude',
      type: ProviderType.anthropic,
      baseUrl: 'https://api.anthropic.com',
      defaultModel: 'claude-sonnet-5-5',
      privacy: PrivacyLevel.standard,
      authMethod: const NoAuth(),
    );
    await _open(tester, const [_opus, _sonnet, _haiku], existing: profile);
    expect(find.text('Empfohlen'), findsOneWidget);
    expect(_field(tester), 'claude-sonnet-5-5');
    expect(
      tester.getTopLeft(find.text('Claude Haiku 5.5')).dy,
      lessThan(tester.getTopLeft(find.text('Claude Sonnet 5.5')).dy),
    );
  });

  testWidgets('Empfehlung nicht in der Liste: keine Plakette, erste '
      'Modell vorausgewählt, freie Wahl bleibt', (tester) async {
    await _open(tester, const [_opus, _sonnet]);
    expect(find.text('Empfohlen'), findsNothing);
    expect(_field(tester), 'claude-opus-5-5');
    await tester.tap(find.text('Claude Sonnet 5.5'));
    await tester.pumpAndSettle();
    expect(_field(tester), 'claude-sonnet-5-5');
  });
}
