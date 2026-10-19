import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/audit_recorder.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';

Future<String> _description({required bool privateDetails}) async {
  final storage = openInMemoryStorage();
  addTearDown(storage.close);
  final recorder = AuditRecorder(storage.audit, clock: const SystemClock());
  recorder.toolConfirmation(
    's',
    ConfirmationRequired(
      call: const ToolCallBlock(
        id: 'c',
        name: 'sms__compose',
        argumentsJson: '{}',
      ),
      description: 'SMS an Anna (+49170)\nGeheimer Text',
      respond: (_) {},
      privateDetails: privateDetails,
    ),
    approved: true,
  );
  await recorder.flush();
  final entries = await storage.audit.query();
  return entries.single.payload['description']! as String;
}

void main() {
  test('Audit: Bestätigung eines Werkzeugs mit privatem Text speichert nur '
      'die erste Zeile', () async {
    final d = await _description(privateDetails: true);
    expect(d, 'SMS an Anna (+49170)');
  });

  test(
    'Audit: gewöhnliche Bestätigung behält die ganze Beschreibung',
    () async {
      final d = await _description(privateDetails: false);
      expect(d, contains('Geheimer Text'));
    },
  );
}
