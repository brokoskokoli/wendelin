import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

/// Locale (BCP 47) and IANA time zone of the device.
Future<DeviceInfo> loadDeviceInfo() async {
  final locale = PlatformDispatcher.instance.locale.toLanguageTag();
  String zone;
  try {
    zone = (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object catch (e) {
    if (e is! PlatformException &&
        e is! MissingPluginException &&
        e is! ArgumentError) {
      rethrow;
    }
    // No IANA name available: UTC keeps instants correct, only the shown
    // local times are off. Logged so it does not go unnoticed.
    debugPrint('Zeitzone nicht lesbar, verwende UTC: $e');
    zone = 'UTC';
  }
  return DeviceInfo(locale: locale, timeZone: zone);
}
