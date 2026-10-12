import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Findet hart kodierte Farben und Abstände in Bausteinen.
///
/// Farben gehören nach `WColors`, Abstände/Größen/Radien nach
/// `WSpace`/`WSize`/`WRadius` (lib/ui/theme/app_theme.dart). Ausgenommen
/// sind Zahlen der Zeichengeometrie in `CustomPainter`-Klassen
/// (SVG-viewBox-Einheiten; Farben werden dort trotzdem geprüft) und die
/// Zahl 0.
List<String> findViolations(String source) {
  final problems = <String>[];
  final code = source
      .replaceAll(RegExp(r'//[^\n]*'), '')
      .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''");

  // Farben: überall, auch in CustomPaintern.
  for (final m in RegExp(
    r'\b(?!WColors\b)\w*Colors\.\w+|\bColor\s*\(\s*\d|\bColor\.from\w+'
    r'|\.withOpacity\s*\(|\.withValues\s*\(\s*alpha\s*:\s*\d',
  ).allMatches(code)) {
    problems.add('Farbe: ${m.group(0)}');
  }

  // Zahlen: nicht in Zeichengeometrie von CustomPaintern (viewBox-Einheiten).
  final layout = _stripPainters(code);
  final number = RegExp(r'(?<![\w.$])(?!0\b|0\.0\b)\d+(?:\.\d+)?\b');
  const calls = [
    'EdgeInsets',
    'EdgeInsetsDirectional',
    'SizedBox',
    'Radius.circular',
    'Radius.elliptical',
    'BorderRadius.circular',
    'Size',
    'BoxConstraints',
    'Offset',
    'Positioned',
    'PositionedDirectional',
  ];
  for (final call in calls) {
    final re = RegExp('\\b${RegExp.escape(call)}(?:\\.\\w+)?\\s*\\(');
    for (final m in re.allMatches(layout)) {
      final args = _balanced(layout, m.end - 1);
      final n = number.firstMatch(args);
      if (n != null) problems.add('$call(…${n.group(0)}…)');
    }
  }
  for (final m in RegExp(
    r'\b(spacing|runSpacing|width|height|size|dimension|radius|fontSize|'
    r'opacity|strokeWidth|letterSpacing|elevation|top|left|right|bottom|'
    r'start|end|scale|thickness|indent)\s*:\s*(\d+(?:\.\d+)?)',
  ).allMatches(layout)) {
    if (double.parse(m.group(2)!) != 0) {
      problems.add('${m.group(1)}: ${m.group(2)}');
    }
  }
  return problems;
}

String _balanced(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')' && --depth == 0) return s.substring(open + 1, i);
  }
  return s.substring(open + 1);
}

String _stripPainters(String code) {
  final re = RegExp(r'class\s+\w+\s+extends\s+CustomPainter\s*\{');
  var out = code;
  RegExpMatch? m;
  while ((m = re.firstMatch(out)) != null) {
    var depth = 0;
    var end = out.length;
    for (var i = m!.end - 1; i < out.length; i++) {
      if (out[i] == '{') depth++;
      if (out[i] == '}' && --depth == 0) {
        end = i + 1;
        break;
      }
    }
    out = out.replaceRange(m.start, end, '');
  }
  return out;
}

void main() {
  test('Bausteine in lib/ui nutzen nur Theme-Konstanten', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('/theme/'))
        .toList();
    expect(files, isNotEmpty);
    final report = <String>[];
    for (final f in files) {
      for (final p in findViolations(f.readAsStringSync())) {
        report.add('${f.path}: $p');
      }
    }
    expect(report, isEmpty, reason: report.join('\n'));
  });

  test('Prüfung erkennt Verstöße (Gegenprobe)', () {
    expect(findViolations('color: Color(0xFF101214)'), isNotEmpty);
    expect(findViolations('color: Colors.white'), isNotEmpty);
    expect(findViolations('padding: EdgeInsets.all(16)'), isNotEmpty);
    expect(
      findViolations('EdgeInsets.symmetric(\n  horizontal: 10,\n)'),
      isNotEmpty,
    );
    expect(findViolations('SizedBox(height: 8)'), isNotEmpty);
    expect(findViolations('BorderRadius.circular(12)'), isNotEmpty);
    expect(findViolations('spacing: 6,'), isNotEmpty);
    expect(findViolations('const Size(44, 44)'), isNotEmpty);
    expect(findViolations('padding: EdgeInsets.all(WSpace.l)'), isEmpty);
    expect(findViolations('EdgeInsets.fromLTRB(WSpace.l, 0, 0, 0)'), isEmpty);
    expect(
      findViolations(
        'class _P extends CustomPainter { void p() { Radius.circular(3); } }',
      ),
      isEmpty,
    );
    expect(findViolations("WIconData._('<rect width=\"17\"/>')"), isEmpty);
    expect(findViolations('color: WColors.ink'), isEmpty);
    expect(findViolations('color: CupertinoColors.white'), isNotEmpty);
    expect(findViolations('Color(4279374356)'), isNotEmpty);
    expect(findViolations('WColors.ink.withOpacity(0.5)'), isNotEmpty);
    expect(findViolations('WColors.ink.withValues(alpha: 0.5)'), isNotEmpty);
    expect(
      findViolations('WColors.ink.withValues(alpha: WOpacity.inactive)'),
      isEmpty,
    );
    expect(findViolations('const Offset(4, 0)'), isNotEmpty);
    expect(findViolations('Radius.elliptical(8, 4)'), isNotEmpty);
    expect(findViolations('Positioned(top: 12, child: x)'), isNotEmpty);
    expect(findViolations('Positioned(left: WSpace.l, child: x)'), isEmpty);
    expect(findViolations('Transform.scale(scale: 1.2)'), isNotEmpty);
    expect(
      findViolations(
        'class _P extends CustomPainter { void p() { Paint()..color = '
        'Colors.red; } }',
      ),
      isNotEmpty,
    );
    expect(
      findViolations(
        'class _P extends CustomPainter { void p() { Offset(10, 3); } }',
      ),
      isEmpty,
    );
  });
}
