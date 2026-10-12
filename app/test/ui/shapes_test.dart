// Plattformunabhängige Absicherung der Formen (ohne Goldens): prüft, was die
// Bausteine tatsächlich auf die Leinwand zeichnen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'helpers.dart';

Future<RenderObject> _render(
  WidgetTester tester,
  Widget w,
  Type paintedBy,
) async {
  await tester.pumpWidget(themed(Scaffold(body: Center(child: w))));
  await tester.pumpAndSettle();
  return tester.renderObject(
    find
        .descendant(of: find.byWidget(w), matching: find.byType(paintedBy))
        .first,
  );
}

void main() {
  group('CheckStatusIcon: Farbe + Form', () {
    testWidgets('geprüft = Kreis (grün) mit Haken', (tester) async {
      final r = await _render(
        tester,
        const CheckStatusIcon(CheckStatus.ok),
        CustomPaint,
      );
      expect(
        r,
        paints
          ..circle(color: WColors.ok)
          ..path(color: WColors.ink),
      );
      expect(r, isNot(paints..rrect()));
    });

    testWidgets('ausstehend = Dreieck (gelb) mit Ausrufezeichen', (
      tester,
    ) async {
      final r = await _render(
        tester,
        const CheckStatusIcon(CheckStatus.pending),
        CustomPaint,
      );
      expect(
        r,
        paints
          ..path(color: WColors.warn)
          ..line(color: WColors.ink)
          ..line(color: WColors.ink),
      );
      expect(r, isNot(paints..circle()));
      expect(r, isNot(paints..rrect()));
    });

    testWidgets('fehlgeschlagen = Quadrat (rot) mit Kreuz', (tester) async {
      final r = await _render(
        tester,
        const CheckStatusIcon(CheckStatus.failed),
        CustomPaint,
      );
      expect(
        r,
        paints
          ..rrect(color: WColors.error)
          ..line(color: WColors.ink)
          ..line(color: WColors.ink),
      );
      expect(r, isNot(paints..circle()));
    });
  });

  group('Glyph: Formen', () {
    const c = WColors.text;
    final cases = <GlyphShape, PaintPattern>{
      GlyphShape.dot: paints..circle(color: c, style: PaintingStyle.fill),
      GlyphShape.ring: paints..circle(color: c, style: PaintingStyle.stroke),
      GlyphShape.diamond: paints..path(color: c, style: PaintingStyle.fill),
      GlyphShape.triangle: paints..path(color: c, style: PaintingStyle.fill),
      GlyphShape.square: paints..rect(color: c),
      GlyphShape.check: paints..path(color: c, style: PaintingStyle.stroke),
      GlyphShape.cross: paints
        ..line(color: c)
        ..line(color: c),
    };
    for (final e in cases.entries) {
      testWidgets('${e.key}', (tester) async {
        final r = await _render(tester, Glyph(e.key, color: c), CustomPaint);
        expect(r, e.value);
      });
    }

    testWidgets('Raute und Dreieck unterscheiden sich', (tester) async {
      final diamond = await _render(
        tester,
        const Glyph(GlyphShape.diamond, color: c, size: 10),
        CustomPaint,
      );
      expect(
        diamond,
        paints..path(
          includes: const [Offset(5, 1), Offset(9, 5), Offset(1, 5)],
          excludes: const [Offset(1, 9)],
        ),
      );
      final triangle = await _render(
        tester,
        const Glyph(GlyphShape.triangle, color: c, size: 10),
        CustomPaint,
      );
      expect(
        triangle,
        paints..path(
          includes: const [Offset(5, 2), Offset(1, 9), Offset(9, 9)],
          excludes: const [Offset(1, 5)],
        ),
      );
    });
  });

  group('PrivacyChip: Füllung / Rahmen / gestrichelt', () {
    testWidgets('lokal: gefüllt (Papier)', (tester) async {
      final r = await _render(
        tester,
        const PrivacyChip(PrivacyLevel.local),
        DecoratedBox,
      );
      expect(r, paints..rrect(color: WColors.paper));
    });

    testWidgets('TEE: durchgezogener Rahmen (Papier), keine Füllung', (
      tester,
    ) async {
      final r = await _render(
        tester,
        const PrivacyChip(PrivacyLevel.tee),
        DecoratedBox,
      );
      expect(r, paints..drrect(color: WColors.paper));
      expect(r, isNot(paints..rrect()));
    });

    testWidgets('EU: durchgezogener Rahmen (lineSubtle)', (tester) async {
      final r = await _render(
        tester,
        const PrivacyChip(PrivacyLevel.eu),
        DecoratedBox,
      );
      expect(r, paints..drrect(color: WColors.lineSubtle));
    });

    testWidgets('Standard: gestrichelt (viele Teilstücke, lineSubtle)', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(
          const Scaffold(
            body: Center(child: PrivacyChip(PrivacyLevel.standard)),
          ),
        ),
      );
      final r = tester.renderObject(
        find
            .descendant(
              of: find.byType(DashedBorder),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(
        r,
        paints
          ..path(color: WColors.lineSubtle, style: PaintingStyle.stroke)
          ..path(color: WColors.lineSubtle, style: PaintingStyle.stroke)
          ..path(color: WColors.lineSubtle, style: PaintingStyle.stroke),
      );
      expect(find.byType(DecoratedBox), findsNothing);
    });
  });

  group('MicButton', () {
    testWidgets('Zuhören: Ring innerhalb der Fläche, kein Überstand', (
      tester,
    ) async {
      final r = await _render(
        tester,
        MicButton(state: MicState.listening, onPressed: () {}),
        CustomPaint,
      );
      const outer = WSize.micButton / 2;
      expect(
        r,
        paints
          ..circle(
            color: WColors.accentLight,
            radius: outer - WSize.micRing / 2,
            style: PaintingStyle.stroke,
          )
          ..circle(
            color: WColors.accent,
            radius: outer - WSize.micRing - WSize.micRingGap,
          ),
      );
      expect(
        tester.getSize(find.byType(MicButton)),
        const Size.square(WSize.micButton),
      );
    });
  });
}
