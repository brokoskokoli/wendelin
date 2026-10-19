@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/quick_switch.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../ui/helpers.dart';

ProviderProfile _p(String id, String name, PrivacyLevel level) =>
    ProviderProfile(
      id: id,
      name: name,
      type: ProviderType.anthropic,
      defaultModel: 'm',
      privacy: level,
      authMethod: const NoAuth(),
    );

void main() {
  testWidgets('Schnellwechsel-Popup', (tester) async {
    setView(tester, const Size(390, 520));
    await tester.pumpWidget(
      themed(
        RepaintBoundary(
          key: goldenKey,
          child: Material(
            color: WColors.surface,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: QuickSwitchSheet(
                currentId: 'phala',
                profiles: [
                  _p('phala', 'Phala · GLM klein', PrivacyLevel.tee),
                  _p('claude', 'Claude Sonnet', PrivacyLevel.standard),
                  _p('eu', 'Mistral · EU', PrivacyLevel.eu),
                  _p('local', 'Lokal · Gemma', PrivacyLevel.local),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/schnellwechsel.png'),
    );
  });
}
