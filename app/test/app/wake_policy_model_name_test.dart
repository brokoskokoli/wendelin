import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// The Kotlin station guard (`WakePolicy.kt`) names the classifier file a
/// second time; both must stay the same as the Dart catalog (WP173).
void main() {
  test('WakePolicy.kt nennt dieselbe Modell-Id und Datei wie der Katalog', () {
    final kt = File(
      'android/app/src/main/kotlin/app/wendelin/WakePolicy.kt',
    ).readAsStringSync();
    String konst(String name) =>
        RegExp('const val $name = "([^"]+)"').firstMatch(kt)![1]!;
    expect(konst('CLASSIFIER_ID'), WakeClassifierCatalog.model.id);
    expect(konst('CLASSIFIER_FILE'), WakeClassifierCatalog.file);
  });
}
