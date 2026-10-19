import 'package:test/test.dart';

import '../src/station/station.dart';

/// Contract of every [StationPort]: [create] returns a port on an unlocked
/// device.
void stationPortContract(StationPort Function() create) {
  group('StationPort', () {
    test('isLocked answers without throwing', () async {
      expect(await create().isLocked(), isA<bool>());
    });
  });
}
