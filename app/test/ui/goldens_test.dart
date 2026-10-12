@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/compositions.dart';
import 'package:wendelin/ui/design/gallery.dart';

import 'helpers.dart';

String _file(String name) =>
    name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

void main() {
  group('Bausteine', () {
    for (final section in gallerySections.entries) {
      testWidgets(section.key, (tester) async {
        await pumpComponent(tester, section.value);
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/components/${_file(section.key)}.png'),
        );
      });
    }
  });

  group('Screens (390 × 844)', () {
    final screens = <String, Widget>{
      'hauptbildschirm': const MainScreenSample(),
      'bestaetigung': const ConfirmationSheetSample(),
      'integrationen': const IntegrationsSample(),
    };
    for (final s in screens.entries) {
      testWidgets(s.key, (tester) async {
        await pumpScreen(tester, s.value);
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('goldens/screens/${s.key}.png'),
        );
      });
    }
  });
}
