import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'helpers.dart';

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(themed(Scaffold(body: Center(child: w))));
  await tester.pumpAndSettle();
}

void main() {
  group('MicButton', () {
    for (final state in MicState.values) {
      testWidgets('$state: Label, Größe, Tippen', (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await _pump(tester, MicButton(state: state, onPressed: () => taps++));
        final label = MicButton.labelFor(AppLocalizationsDe(), state);
        expect(find.byTooltip(label), findsOneWidget);
        // Genau eine Ansage: Tooltip, kein zusätzliches Label.
        final data = tester
            .getSemantics(find.byType(IconButton))
            .getSemanticsData();
        expect(data.tooltip, label);
        expect(data.label, isEmpty);
        expect(data.flagsCollection.isButton, isTrue);
        expect(tester.getSize(find.byType(IconButton)), const Size(72, 72));
        await tester.tap(find.byType(MicButton));
        expect(taps, state == MicState.disabled ? 0 : 1);
        handle.dispose();
      });
    }

    testWidgets('kompakt ist 64, eigenes Label möglich', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        MicButton(
          state: MicState.idle,
          onPressed: () {},
          compact: true,
          semanticLabel: 'Weiter sprechen',
        ),
      );
      expect(tester.getSize(find.byType(IconButton)), const Size(64, 64));
      final data = tester
          .getSemantics(find.byType(IconButton))
          .getSemanticsData();
      expect(data.tooltip, 'Weiter sprechen');
      expect(data.label, isEmpty);
      handle.dispose();
    });

    testWidgets('Punkte statt Mikrofon bei „thinking“ und „speaking“', (
      tester,
    ) async {
      for (final state in [MicState.thinking, MicState.speaking]) {
        await _pump(tester, MicButton(state: state, onPressed: () {}));
        expect(find.byType(WIcon), findsNothing, reason: '$state');
      }
      // Vorbereiten zeigt das Mikrofon (mit gedämpftem Ring).
      await _pump(
        tester,
        MicButton(state: MicState.preparing, onPressed: () {}),
      );
      expect(find.byType(WIcon), findsOneWidget);
      await _pump(tester, MicButton(state: MicState.idle, onPressed: () {}));
      expect(find.byType(WIcon), findsOneWidget);
    });
  });

  group('MicButton „hört mit“ (WP113)', () {
    CustomPaint paint(WidgetTester tester) => tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(MicButton),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

    testWidgets('Ring und Hinweis nur beim Sprechen mit hearing', (
      tester,
    ) async {
      await _pump(
        tester,
        MicButton(state: MicState.speaking, onPressed: () {}),
      );
      expect(paint(tester).painter, isNull);
      expect(find.byTooltip('Sprachausgabe stoppen'), findsOneWidget);

      await _pump(
        tester,
        MicButton(state: MicState.speaking, hearing: true, onPressed: () {}),
      );
      expect(paint(tester).painter, isNotNull);
      expect(find.byTooltip(AppLocalizationsDe().mainMicHearing), findsOne);

      // Not speaking: hearing alone shows nothing.
      await _pump(
        tester,
        MicButton(state: MicState.idle, hearing: true, onPressed: () {}),
      );
      expect(paint(tester).painter, isNull);
    });
  });

  group('ToolResultCard rückgängig', () {
    testWidgets('Hinweis statt Button, durchgestrichen', (tester) async {
      await _pump(
        tester,
        ToolResultCard(
          title: 'Termin angelegt',
          detail: 'Tauchen',
          toolName: 'calendar__create_event',
          undone: true,
          onUndo: () {},
          undoRemaining: const Duration(seconds: 5),
        ),
      );
      expect(find.text('Rückgängig gemacht'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      final title = tester.widget<Text>(find.text('Termin angelegt'));
      expect(title.style!.decoration, TextDecoration.lineThrough);
    });
  });

  group('MicButton speaking', () {
    Offset firstDot(WidgetTester tester) => tester.getTopLeft(
      find
          .descendant(
            of: find.byType(MicButton),
            matching: find.byType(DecoratedBox),
          )
          .last,
    );

    Future<void> pumpSpeaking(WidgetTester tester, {required bool animate}) =>
        tester.pumpWidget(
          themed(
            Scaffold(
              body: Center(
                child: MicButton(state: MicState.speaking, onPressed: () {}),
              ),
            ),
            animations: animate,
          ),
        );

    testWidgets('die Punkte bewegen sich', (tester) async {
      await pumpSpeaking(tester, animate: true);
      final ys = <double>{};
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 75));
        ys.add(firstDot(tester).dy);
      }
      expect(ys.length, greaterThan(1));
      // Entfernt man den Knopf, endet die Animation (kein offener Ticker).
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bei abgeschalteten Animationen stehen sie still', (
      tester,
    ) async {
      await pumpSpeaking(tester, animate: false);
      final ys = <double>{};
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 75));
        ys.add(firstDot(tester).dy);
      }
      expect(ys, hasLength(1));
      await tester.pumpAndSettle();
    });

    testWidgets('Label „Sprachausgabe stoppen“, vorbereiten „Moment …“', (
      tester,
    ) async {
      expect(
        MicButton.labelFor(AppLocalizationsDe(), MicState.speaking),
        'Sprachausgabe stoppen',
      );
      expect(
        MicButton.labelFor(AppLocalizationsDe(), MicState.preparing),
        'Moment …',
      );
    });
  });

  group('Waveform', () {
    testWidgets('ein Balken je Amplitude (4 breit, Abstand 4)', (tester) async {
      await _pump(tester, const Waveform(amplitudes: [0.1, 0.5, 1]));
      expect(tester.getSize(find.byType(Waveform)), const Size(20, 40));
      await _pump(tester, const Waveform(amplitudes: []));
      expect(tester.getSize(find.byType(Waveform)), const Size(0, 40));
    });
  });

  group('Chips', () {
    testWidgets('PrivacyChip trägt Name und Stufe', (tester) async {
      final handle = tester.ensureSemantics();
      for (final l in PrivacyLevel.values) {
        await _pump(tester, PrivacyChip(l));
        expect(find.text(l.labelOf(AppLocalizationsDe())), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            '${l.labelOf(AppLocalizationsDe())}, Datenschutzstufe ${l.labelOf(AppLocalizationsDe())}',
          ),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('Form je Stufe: gefüllt / Rahmen / gestrichelt', (
      tester,
    ) async {
      await _pump(tester, const PrivacyChip(PrivacyLevel.local));
      final local = tester.widget<Container>(find.byType(Container).first);
      expect((local.decoration! as BoxDecoration).color, WColors.paper);
      await _pump(tester, const PrivacyChip(PrivacyLevel.tee));
      final tee = tester.widget<Container>(find.byType(Container).first);
      expect((tee.decoration! as BoxDecoration).color, isNull);
      expect(
        (tee.decoration! as BoxDecoration).border!.top.color,
        WColors.paper,
      );
      expect(find.byType(DashedBorder), findsNothing);
      await _pump(tester, const PrivacyChip(PrivacyLevel.standard));
      expect(find.byType(DashedBorder), findsOneWidget);
      expect(tester.widget<Glyph>(find.byType(Glyph)).shape, GlyphShape.ring);
    });

    test('Symbole je Stufe', () {
      expect(GlyphShape.forPrivacy(PrivacyLevel.local), GlyphShape.dot);
      expect(GlyphShape.forPrivacy(PrivacyLevel.tee), GlyphShape.diamond);
      expect(GlyphShape.forPrivacy(PrivacyLevel.eu), GlyphShape.triangle);
      expect(GlyphShape.forPrivacy(PrivacyLevel.standard), GlyphShape.ring);
    });

    testWidgets('ProviderChip mit und ohne Prüfstatus', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const ProviderChip(
          name: 'Phala · GLM klein',
          level: PrivacyLevel.tee,
          status: CheckStatus.ok,
        ),
      );
      expect(find.byType(CheckStatusIcon), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Provider Phala · GLM klein, Datenschutzstufe TEE, Quittung geprüft',
        ),
        findsOneWidget,
      );
      await _pump(
        tester,
        const ProviderChip(name: 'Claude Haiku', level: PrivacyLevel.standard),
      );
      expect(find.byType(CheckStatusIcon), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Provider Claude Haiku, Datenschutzstufe Standard',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('ToolChip: Form und Farbe je Status', (tester) async {
      final expected = {
        CheckStatus.ok: (GlyphShape.check, WColors.textMuted),
        CheckStatus.pending: (GlyphShape.triangle, WColors.warn),
        CheckStatus.failed: (GlyphShape.cross, WColors.error),
      };
      for (final e in expected.entries) {
        await _pump(tester, ToolChip('a__b', status: e.key));
        final g = tester.widget<Glyph>(find.byType(Glyph));
        expect((g.shape, g.color), e.value);
        expect(find.text('a__b'), findsOneWidget);
      }
    });
  });

  group('CheckStatusIcon', () {
    testWidgets('Label und Farbe je Status', (tester) async {
      final handle = tester.ensureSemantics();
      for (final s in CheckStatus.values) {
        await _pump(tester, CheckStatusIcon(s));
        expect(
          find.bySemanticsLabel(s.labelOf(AppLocalizationsDe())),
          findsOneWidget,
        );
      }
      expect(CheckStatus.ok.color, WColors.ok);
      expect(CheckStatus.pending.color, WColors.warn);
      expect(CheckStatus.failed.color, WColors.error);
      expect(CheckStatus.info.color, WColors.textMuted);
      handle.dispose();
    });
  });

  group('ToolResultCard', () {
    ToolResultCard card(Duration? remaining, VoidCallback? onUndo) =>
        ToolResultCard(
          title: 'Termin angelegt',
          detail: 'Tauchen',
          toolName: 'calendar__create_event',
          onUndo: onUndo,
          undoRemaining: remaining,
        );

    test('Restsekunden werden aufgerundet', () {
      expect(card(const Duration(milliseconds: 7001), null).undoSeconds, 8);
      expect(card(const Duration(seconds: 8), null).undoSeconds, 8);
      expect(card(const Duration(milliseconds: 1), null).undoSeconds, 1);
      expect(card(Duration.zero, null).undoSeconds, 0);
      expect(card(const Duration(seconds: -1), null).undoSeconds, 0);
      expect(card(null, null).undoSeconds, 0);
    });

    testWidgets('Rückgängig mit Countdown, tippbar', (tester) async {
      var undone = 0;
      await _pump(tester, card(const Duration(seconds: 8), () => undone++));
      expect(find.text('Rückgängig · 8 s'), findsOneWidget);
      expect(find.text('calendar__create_event'), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      expect(undone, 1);
      expect(
        tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(WSize.touchMin),
      );
    });

    testWidgets('ohne Restzeit oder Aktion kein Button', (tester) async {
      await _pump(tester, card(Duration.zero, () {}));
      expect(find.byType(OutlinedButton), findsNothing);
      await _pump(tester, card(const Duration(seconds: 5), null));
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('ConfirmationCard', () {
    testWidgets('Ja / Nein, Tool-Name und Stufe', (tester) async {
      final calls = <String>[];
      await _pump(
        tester,
        ConfirmationCard(
          title: 'Termin löschen?',
          subject: 'Zahnarzt Dr. Weber',
          detail: 'Do 15.10.',
          toolName: 'calendar__delete_event',
          risk: RiskLevel.external,
          onYes: () => calls.add('ja'),
          onNo: () => calls.add('nein'),
          yesLabel: 'Ja, löschen',
          noLabel: 'Nein, behalten',
        ),
      );
      expect(find.text('BRAUCHT DEINE BESTÄTIGUNG'), findsOneWidget);
      expect(find.text('Zahnarzt Dr. Weber'), findsOneWidget);
      expect(
        find.text('calendar__delete_event · Stufe external'),
        findsOneWidget,
      );
      final icon = tester.widget<CheckStatusIcon>(find.byType(CheckStatusIcon));
      expect(icon.status, CheckStatus.pending);
      await tester.tap(find.text('Nein, behalten'));
      await tester.tap(find.text('Ja, löschen'));
      expect(calls, ['nein', 'ja']);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        WSize.buttonHeightLarge,
      );
    });

    testWidgets('ohne Objekt nur Detail; Rahmen gelb', (tester) async {
      await _pump(
        tester,
        ConfirmationCard(
          title: 'SMS senden?',
          detail: '„Bin gleich da.“',
          toolName: 'sms__send',
          risk: RiskLevel.external,
          onYes: () {},
          onNo: () {},
        ),
      );
      expect(find.text('Ja'), findsOneWidget);
      expect(find.text('Nein'), findsOneWidget);
      final box = tester.widget<Container>(find.byType(Container).first);
      final border = (box.decoration! as BoxDecoration).border!;
      expect(border.top.color, WColors.warn);
    });
  });

  group('Verlauf', () {
    testWidgets('UserBubble rechts, max. 80 % + Innenabstand', (tester) async {
      setView(tester, const Size(400, 400));
      await _pump(tester, UserBubble('x' * 200));
      final size = tester.getSize(find.byType(DecoratedBox).last);
      expect(size.width, lessThanOrEqualTo(400 * 0.8 + 28));
      final short = UserBubble('Hallo', key: UniqueKey());
      await _pump(tester, short);
      final rect = tester.getRect(find.text('Hallo'));
      expect(rect.right, greaterThan(350));
    });

    testWidgets('AssistantText: Link nur mit Aktion, tippbar', (tester) async {
      var opened = 0;
      await _pump(
        tester,
        AssistantText(
          'Fertig.',
          linkLabel: 'Öffnen',
          onLinkTap: () => opened++,
        ),
      );
      expect(find.textContaining('Öffnen', findRichText: true), findsOneWidget);
      await tester.tapOnText(find.textRange.ofSubstring('Öffnen'));
      expect(opened, 1);
      await _pump(tester, const AssistantText('Fertig.', linkLabel: 'Öffnen'));
      expect(find.text('Fertig.'), findsOneWidget);
    });

    testWidgets('AssistantText groß nutzt Antwortstil', (tester) async {
      await _pump(tester, const AssistantText('A', large: true));
      expect(tester.widget<Text>(find.text('A')).style, WText.answer);
      await _pump(tester, const AssistantText('A'));
      expect(tester.widget<Text>(find.text('A')).style, WText.chatAnswer);
    });

    testWidgets('EscalationDivider zeigt den Text zwischen Linien', (
      tester,
    ) async {
      await _pump(tester, const EscalationDivider('an Sonnet übergeben'));
      expect(find.text('an Sonnet übergeben'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EscalationDivider),
          matching: find.byType(ColoredBox),
        ),
        findsNWidgets(2),
      );
    });
  });

  group('IntegrationTile', () {
    Future<void> pumpTile(WidgetTester tester, IntegrationTile tile) =>
        _pump(tester, SectionCard(children: [tile]));

    testWidgets('aktiv: Schalter an, grüner Punkt, Umschalten', (tester) async {
      bool? toggled;
      await pumpTile(
        tester,
        IntegrationTile(
          name: 'Kalender',
          icon: WIcons.calendar,
          status: IntegrationStatus.active,
          detail: '6 Tools',
          onToggle: (v) => toggled = v,
        ),
      );
      expect(
        find.textContaining('Aktiv · 6 Tools', findRichText: true),
        findsOneWidget,
      );
      final glyph = tester.widget<Glyph>(find.byType(Glyph));
      expect((glyph.shape, glyph.color), (GlyphShape.dot, WColors.ok));
      expect(tester.widget<WSwitch>(find.byType(WSwitch)).value, isTrue);
      await tester.tap(find.byType(WSwitch));
      expect(toggled, isFalse);
    });

    testWidgets('verfügbar: Schalter aus; sensibel mit Mindeststufe', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      bool? toggled;
      await pumpTile(
        tester,
        IntegrationTile(
          name: 'Kontakte',
          icon: WIcons.person,
          status: IntegrationStatus.available,
          sensitive: true,
          minPrivacy: PrivacyLevel.tee,
          onToggle: (v) => toggled = v,
        ),
      );
      expect(find.text('sensibel'), findsOneWidget);
      expect(find.bySemanticsLabel('Kontakte, sensibel'), findsOneWidget);
      expect(
        find.textContaining('Nur an Provider ab', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester.widget<Glyph>(find.byType(Glyph)).shape,
        GlyphShape.diamond,
      );
      await tester.tap(find.byType(WSwitch));
      expect(toggled, isTrue);
      handle.dispose();
    });

    testWidgets('verfügbar ohne Mindeststufe: „Verfügbar“', (tester) async {
      await pumpTile(
        tester,
        const IntegrationTile(
          name: 'Wetter',
          icon: WIcons.waves,
          status: IntegrationStatus.available,
        ),
      );
      expect(
        find.textContaining('Verfügbar', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('sensibel'), findsNothing);
    });

    for (final (state, label, color, shape) in [
      (
        IntegrationStatus.setupRequired,
        'Einrichten',
        WColors.warn,
        GlyphShape.triangle,
      ),
      (
        IntegrationStatus.error,
        'Neu anmelden',
        WColors.error,
        GlyphShape.square,
      ),
    ]) {
      testWidgets('$state: Button „$label“ in Statusfarbe', (tester) async {
        var pressed = 0;
        await pumpTile(
          tester,
          IntegrationTile(
            name: 'X',
            icon: WIcons.cart,
            status: state,
            detail: 'Grund',
            onAction: () => pressed++,
          ),
        );
        expect(find.byType(WSwitch), findsNothing);
        final glyph = tester.widget<Glyph>(find.byType(Glyph));
        expect((glyph.shape, glyph.color), (shape, color));
        final button = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(button.style!.side!.resolve({})!.color, color);
        await tester.tap(find.text(label));
        expect(pressed, 1);
      });
    }

    testWidgets('unavailable: gedämpft, Store-Link', (tester) async {
      var store = 0;
      await pumpTile(
        tester,
        IntegrationTile(
          name: 'Todoist',
          icon: WIcons.task,
          status: IntegrationStatus.unavailable,
          detail: 'App nicht installiert',
          onStore: () => store++,
        ),
      );
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        WOpacity.inactive,
      );
      expect(
        find.textContaining('App nicht installiert', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Im Store'));
      expect(store, 1);
      await pumpTile(
        tester,
        const IntegrationTile(
          name: 'Todoist',
          icon: WIcons.task,
          status: IntegrationStatus.unavailable,
        ),
      );
      expect(find.text('Im Store'), findsNothing);
      expect(
        find.textContaining('Nicht verfügbar', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('Zeilenhöhe 66 wie im Entwurf', (tester) async {
      await pumpTile(
        tester,
        IntegrationTile(
          name: 'Kalender',
          icon: WIcons.calendar,
          status: IntegrationStatus.active,
          onToggle: (_) {},
        ),
      );
      expect(tester.getSize(find.byType(IntegrationTile)).height, 66);
    });
  });

  group('WSwitch', () {
    testWidgets('Semantics: toggled, Label, deaktiviert ohne Callback', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        WSwitch(value: true, onChanged: (_) {}, semanticLabel: 'Kalender'),
      );
      expect(
        tester.getSemantics(find.byType(WSwitch)),
        matchesSemantics(
          label: 'Kalender',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      await _pump(
        tester,
        const WSwitch(value: false, onChanged: null, semanticLabel: 'Aus'),
      );
      expect(
        tester.getSemantics(find.byType(WSwitch)),
        matchesSemantics(
          label: 'Aus',
          hasToggledState: true,
          hasEnabledState: true,
        ),
      );
      expect(tester.getSize(find.byType(WSwitch)), const Size(52, 48));
      handle.dispose();
    });
  });

  group('RuleTile', () {
    testWidgets('aktiv mit Kobalt-Rahmen, Default gestrichelt', (tester) async {
      await _pump(
        tester,
        const RuleTile(name: 'Privat', condition: 'keyword', active: true),
      );
      final shape =
          tester.widget<Material>(find.byType(Material).last).shape!
              as RoundedRectangleBorder;
      expect(shape.side.color, WColors.accent);
      expect(find.byType(DashedBorder), findsNothing);
      await _pump(
        tester,
        const RuleTile(name: 'Default', condition: 'immer', isDefault: true),
      );
      expect(find.byType(DashedBorder), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
    });

    testWidgets('mit Index ziehbar (außer Default)', (tester) async {
      await _pump(
        tester,
        const RuleTile(name: 'A', condition: 'c', reorderIndex: 0),
      );
      expect(find.byType(ReorderableDragStartListener), findsOneWidget);
      await _pump(
        tester,
        const RuleTile(
          name: 'D',
          condition: 'c',
          reorderIndex: 3,
          isDefault: true,
        ),
      );
      expect(find.byType(ReorderableDragStartListener), findsNothing);
    });
  });

  group('RuleTile: Ziel mit Datenschutz-Symbol', () {
    testWidgets('„→ ◆ Phala GLM“', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const RuleTile(
          name: 'Privat',
          condition: 'keyword "privat"',
          target: 'Phala GLM',
          targetLevel: PrivacyLevel.tee,
        ),
      );
      expect(
        find.textContaining('keyword "privat" → ', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester.widget<Glyph>(find.byType(Glyph)).shape,
        GlyphShape.diamond,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('keyword "privat" → Datenschutzstufe TEE, Phala GLM'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('ohne Stufe kein Symbol, ohne Ziel nur Bedingung', (
      tester,
    ) async {
      await _pump(
        tester,
        const RuleTile(name: 'S', condition: 'prefix "Claude"', target: 'Opus'),
      );
      expect(find.byType(Glyph), findsNothing);
      expect(
        find.textContaining('prefix "Claude" → Opus', findRichText: true),
        findsOneWidget,
      );
      await _pump(tester, const RuleTile(name: 'S', condition: 'immer'));
      expect(find.text('immer'), findsOneWidget);
    });
  });

  test('VerificationStatus → CheckStatus', () {
    expect(VerificationStatus.verified.checkStatus, CheckStatus.ok);
    expect(VerificationStatus.pending.checkStatus, CheckStatus.pending);
    expect(VerificationStatus.failed.checkStatus, CheckStatus.failed);
    expect(VerificationStatus.unavailable.checkStatus, isNull);
  });

  group('SectionCard', () {
    testWidgets('Trenner nur zwischen Kindern, optional Titel', (tester) async {
      await _pump(
        tester,
        const SectionCard(children: [Text('a'), Text('b'), Text('c')]),
      );
      expect(find.byType(Divider), findsNWidgets(2));
      await _pump(
        tester,
        const SectionCard(
          title: 'Titel',
          dividers: false,
          children: [Text('a'), Text('b')],
        ),
      );
      expect(find.byType(Divider), findsNothing);
      expect(find.text('Titel'), findsOneWidget);
    });
  });

  group('Icon-Buttons', () {
    testWidgets('Tooltip, 44er Fläche, Trefferfläche 48', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        WIconButton(
          icon: WIcons.settings,
          tooltip: 'Einstellungen',
          onPressed: () => taps++,
        ),
      );
      expect(find.byTooltip('Einstellungen'), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(IconButton))
          .getSemanticsData();
      expect((data.tooltip, data.label), ('Einstellungen', ''));
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
      await tester.tap(find.byType(IconButton));
      expect(taps, 1);
    });
  });
}
