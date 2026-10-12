import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/main.dart';
import 'package:wendelin/ui/design/gallery.dart';
import 'package:wendelin/ui/design/logo.dart';

void main() {
  testWidgets('Debug zeigt die Galerie', (tester) async {
    await tester.pumpWidget(const MainApp(showGallery: true));
    await tester.pumpAndSettle();
    expect(find.byType(DesignGallery), findsOneWidget);
  });

  testWidgets('Release zeigt den Platzhalter mit Lockup', (tester) async {
    await tester.pumpWidget(const MainApp(showGallery: false));
    await tester.pumpAndSettle();
    expect(find.byType(DesignGallery), findsNothing);
    expect(find.byType(PlaceholderHome), findsOneWidget);
    expect(find.byType(WendelinLockup), findsOneWidget);
  });

  test('Standard folgt dem Build-Modus (Tests laufen in Debug)', () {
    expect(const MainApp().showGallery, isTrue);
  });
}
