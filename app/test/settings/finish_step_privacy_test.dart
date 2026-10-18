import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/privacy_chip.dart';
import 'package:wendelin/ui/settings/provider_setup/finish_step.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart' show GpuCheckMode;

Future<void> _pump(WidgetTester tester, {required bool attested}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: finishStep(
              l: AppLocalizationsDe(),
              result: null,
              detected: null,
              privacy: PrivacyLevel.standard,
              onPrivacy: (_) {},
              budget: TextEditingController(),
              budgetError: null,
              warn: 0.8,
              onWarn: (_) {},
              attested: attested,
              gpuMode: GpuCheckMode.off,
              onGpuMode: (_) {},
              noGpuEvidence: false,
              onSave: () {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('Stufe TEE nur für geprüfte Profile', (tester) async {
    await _pump(tester, attested: false);
    expect(
      find.text(PrivacyLevel.tee.labelOf(AppLocalizationsDe())),
      findsNothing,
    );
    expect(find.text('Ohne Tools (alles verschlüsselt)'), findsNothing);
    expect(
      find.text(PrivacyLevel.standard.labelOf(AppLocalizationsDe())),
      findsWidgets,
    );
    await _pump(tester, attested: true);
    expect(
      find.text(PrivacyLevel.tee.labelOf(AppLocalizationsDe())),
      findsWidgets,
    );
  });
}
