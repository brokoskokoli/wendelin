import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/list_access.dart';
import 'package:wendelin/platform/saf_list_file_port.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _files = MethodChannel(filesChannelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lists = [
    ListDefinition(id: 'a', name: 'Einkaufen', target: 'content://a'),
    ListDefinition(id: 'b', name: 'SmartSSH', target: 'content://b'),
  ];

  void answer(Future<Object?> Function(MethodCall)? handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_files, handler);

  tearDown(() => answer(null));

  test('ohne Plattform-Implementierung (MissingPlugin): keine Liste ohne '
      'Zugriff', () async {
    answer(null);
    expect(await listsWithoutAccess(const DocumentPicker(), lists), isEmpty);
  });

  test('Plattform meldet unsupported: keine Liste ohne Zugriff', () async {
    answer((_) async => throw PlatformException(code: 'unsupported'));
    expect(await listsWithoutAccess(const DocumentPicker(), lists), isEmpty);
  });

  test('andere Fehler und fehlende Rechte zählen als kein Zugriff', () async {
    answer((call) async {
      final uri = (call.arguments as Map<Object?, Object?>)['uri'];
      if (uri == 'content://a') throw PlatformException(code: 'failed');
      return false;
    });
    expect(await listsWithoutAccess(const DocumentPicker(), lists), {'a', 'b'});
  });

  test('alle Rechte vorhanden: leer', () async {
    answer((_) async => true);
    expect(await listsWithoutAccess(const DocumentPicker(), lists), isEmpty);
  });
}
