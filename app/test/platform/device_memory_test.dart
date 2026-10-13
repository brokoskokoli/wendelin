import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/device_memory.dart';

void main() {
  const meminfo =
      'MemTotal:        3854120 kB\n'
      'MemFree:          123456 kB\n'
      'MemAvailable:    1234567 kB\n';

  test('MemTotal aus /proc/meminfo', () async {
    expect(parseMemTotal(meminfo), 3854120 * 1024);
    expect(await deviceTotalMemory(read: () async => meminfo), 3854120 * 1024);
    expect(parseMemTotal('MemFree: 1 kB\n'), isNull);
    expect(parseMemTotal(''), isNull);
  });

  test('nicht lesbar oder kein Android: unbekannt', () async {
    expect(
      await deviceTotalMemory(
        read: () async => throw const FileSystemException('weg'),
      ),
      isNull,
    );
    // Der Testrechner ist kein Android.
    expect(await deviceTotalMemory(), isNull);
  });

  test('wenig Speicher unter 3,5 GiB', () {
    const gib = 1024 * 1024 * 1024;
    expect(isLowMemory(null), isFalse);
    expect(isLowMemory(3 * gib), isTrue);
    expect(isLowMemory(lowMemoryBytes - 1), isTrue);
    expect(isLowMemory(lowMemoryBytes), isFalse);
    // Ein „4-GB-Telefon“ meldet etwa 3,7 GiB.
    expect(isLowMemory(3854120 * 1024), isFalse);
  });
}
