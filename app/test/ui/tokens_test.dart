import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

/// Liest docs/design/tokens.json (Quelle der Wahrheit).
Map<String, Object?> _tokens() {
  final file = File('../docs/design/tokens.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

Color _hex(String v) => Color(int.parse('FF${v.substring(1)}', radix: 16));

num _num(Map<String, Object?> m, String k) => m[k]! as num;

void main() {
  final tokens = _tokens();

  test('jede Farbe aus tokens.json steht gleich in WColors', () {
    final color = tokens['color']! as Map<String, Object?>;
    final expected = <String, Color>{};
    void collect(String prefix, Map<String, Object?> m) {
      for (final e in m.entries) {
        final v = e.value;
        if (v is! Map<String, Object?>) continue;
        final value = v['value'];
        if (value is String) {
          expected['$prefix${e.key}'] = _hex(value);
        } else {
          collect('$prefix${e.key}.', v);
        }
      }
    }

    collect('', color);
    expect(expected, hasLength(17));
    expect(wColorTokens, equals(expected));
  });

  test('WSpace entspricht space', () {
    final s = tokens['space']! as Map<String, Object?>;
    expect(WSpace.xs, _num(s, 'xs'));
    expect(WSpace.s, _num(s, 's'));
    expect(WSpace.m, _num(s, 'm'));
    expect(WSpace.l, _num(s, 'l'));
    expect(WSpace.xl, _num(s, 'xl'));
    expect(WSpace.xxl, _num(s, 'xxl'));
    expect(WSpace.screen, _num(s, 'screenPadding'));
    expect(s.keys.toSet(), {
      'xs', 's', 'm', 'l', 'xl', 'xxl', 'screenPadding', //
    });
  });

  test('WRadius entspricht radius', () {
    final r = tokens['radius']! as Map<String, Object?>;
    expect(WRadius.chip, _num(r, 'chip'));
    expect(WRadius.small, _num(r, 'small'));
    expect(WRadius.button, _num(r, 'button'));
    expect(WRadius.buttonLarge, _num(r, 'buttonLarge'));
    expect(WRadius.card, _num(r, 'card'));
    expect(WRadius.cardLarge, _num(r, 'cardLarge'));
    expect(WRadius.sheet, _num(r, 'sheet'));
  });

  test('WSize entspricht size', () {
    final z = tokens['size']! as Map<String, Object?>;
    expect(WSize.touchMin, _num(z, 'touchMin'));
    expect(WSize.micButton, _num(z, 'micButton'));
    expect(WSize.micButtonCompact, _num(z, 'micButtonCompact'));
    expect(WSize.secondaryRound, _num(z, 'secondaryRound'));
    expect(WSize.buttonHeight, _num(z, 'buttonHeight'));
    expect(WSize.buttonHeightLarge, _num(z, 'buttonHeightLarge'));
    expect([WSize.switchWidth, WSize.switchHeight], z['switch']);
  });

  test('WMotion entspricht motion', () {
    final m = tokens['motion']! as Map<String, Object?>;
    expect(WMotion.undoWindow.inSeconds, _num(m, 'undoWindowSeconds'));
    expect(WMotion.followUpListen.inSeconds, _num(m, 'followUpListenSeconds'));
  });

  test('WText entspricht type', () {
    final type = tokens['type']! as Map<String, Object?>;
    final styles = <String, TextStyle>{
      'transcript': WText.transcript,
      'screenTitle': WText.screenTitle,
      'cardTitle': WText.cardTitle,
      'answer': WText.answer,
      'body': WText.body,
      'label': WText.label,
      'button': WText.button,
      'caption': WText.caption,
      'mono': WText.mono,
    };
    expect(styles.keys.toSet(), type.keys.toSet());
    for (final e in styles.entries) {
      final t = type[e.key]! as Map<String, Object?>;
      final style = e.value;
      final family = t['font'] == 'mono' ? WFonts.mono : WFonts.ui;
      expect(style.fontFamily, family, reason: e.key);
      expect(style.fontSize, t['size'], reason: e.key);
      expect(style.fontWeight!.value, t['weight'], reason: e.key);
      // Ohne Token-Zeilenhöhe: CSS „normal“ (Ascent + Descent, gerundet).
      final size = (t['size']! as num).toDouble();
      expect(
        style.height,
        t['lineHeight'] ?? WText.normalHeight(family, size),
        reason: e.key,
      );
      final ls = (t['letterSpacing'] as num?) ?? 0;
      expect(
        style.letterSpacing ?? 0,
        closeTo(ls * (t['size']! as num), 1e-9),
        reason: e.key,
      );
    }
  });

  test('Zeilenhöhe „normal“ folgt den Font-Metriken und rundet', () {
    expect(WText.normalHeight(WFonts.mono, 12) * 12, 16);
    expect(WText.normalHeight(WFonts.ui, 16) * 16, 20);
    expect(WText.normalHeight(WFonts.ui, 13) * 13, 16);
    expect(WText.normalHeight(WFonts.ui, 26) * 26, 32);
  });

  test('Schriften: alle Gewichte als Asset deklariert, OFL liegt bei', () {
    final font = tokens['font']! as Map<String, Object?>;
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final key in ['ui', 'mono']) {
      final weights = (font[key]! as Map<String, Object?>)['weights']! as List;
      final family = key == 'ui' ? WFonts.ui : WFonts.mono;
      final files = WFonts.files[family]!;
      expect(files, hasLength(weights.length), reason: family);
      for (final f in files) {
        expect(File(f).existsSync(), isTrue, reason: f);
        expect(pubspec, contains('asset: $f'));
      }
      for (final w in weights) {
        expect(pubspec, contains('weight: $w'));
      }
    }
    for (final license in WFonts.licenses.values) {
      expect(
        File(license).readAsStringSync(),
        contains('SIL Open Font License'),
      );
    }
  });
}
