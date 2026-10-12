import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/logo.dart';

import 'helpers.dart';

String _asset(WidgetTester tester) {
  final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
  return (svg.bytesLoader as SvgAssetLoader).assetName;
}

void main() {
  test('alle Logo-Varianten liegen als Asset vor', () async {
    for (final name in [
      'wendelin-mark',
      'wendelin-mark-on-dark',
      'wendelin-mark-white',
      'wendelin-wordmark',
      'wendelin-wordmark-on-dark',
      'wendelin-wordmark-white',
      'wendelin-lockup',
      'wendelin-lockup-on-dark',
    ]) {
      final svg = await rootBundle.loadString('assets/logo/$name.svg');
      expect(svg, startsWith('<svg'), reason: name);
    }
  });

  testWidgets('Variante folgt dem Untergrund', (tester) async {
    final cases = {
      const WendelinMark(): 'assets/logo/wendelin-mark-on-dark.svg',
      const WendelinMark(on: LogoOn.light): 'assets/logo/wendelin-mark.svg',
      const WendelinMark(on: LogoOn.accent):
          'assets/logo/wendelin-mark-white.svg',
      const WendelinWordmark(): 'assets/logo/wendelin-wordmark-on-dark.svg',
      const WendelinWordmark(on: LogoOn.accent):
          'assets/logo/wendelin-wordmark-white.svg',
      const WendelinLockup(): 'assets/logo/wendelin-lockup-on-dark.svg',
      const WendelinLockup(on: LogoOn.light): 'assets/logo/wendelin-lockup.svg',
    };
    for (final c in cases.entries) {
      await tester.pumpWidget(themed(c.key));
      expect(_asset(tester), c.value);
    }
  });

  testWidgets('Schriftzug und Lockup heißen „wendelin“ für Screenreader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(themed(const WendelinLockup()));
    expect(find.bySemanticsLabel('wendelin'), findsOneWidget);
    handle.dispose();
  });
}
