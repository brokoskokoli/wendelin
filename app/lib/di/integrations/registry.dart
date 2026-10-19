import 'alarms_spec.dart';
import 'bring_spec.dart';
import 'calendar_spec.dart';
import 'clipboard_spec.dart';
import 'contacts_spec.dart';
import 'flashlight_spec.dart';
import 'ha_spec.dart';
import 'integration_spec.dart';
import 'lists_spec.dart';
import 'location_spec.dart';
import 'maps_spec.dart';
import 'media_spec.dart';
import 'memory_spec.dart';
import 'obsidian_spec.dart';
import 'spotify_spec.dart';
import 'tasks_spec.dart';
import 'weather_spec.dart';
import 'web_spec.dart';

/// The built-in integrations, in display order: one line per integration.
final builtInIntegrationSpecs = <IntegrationSpec>[
  calendarSpec,
  clipboardSpec,
  alarmsSpec,
  flashlightSpec,
  memorySpec,
  webSpec,
  obsidianSpec,
  bringSpec,
  listsSpec,
  mediaSpec,
  locationSpec,
  mapsSpec,
  haSpec,
  spotifySpec,
  weatherSpec,
  tasksSpec,
  contactsSpec,
];
