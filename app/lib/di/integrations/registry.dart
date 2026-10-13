import 'alarms_spec.dart';
import 'bring_spec.dart';
import 'calendar_spec.dart';
import 'clipboard_spec.dart';
import 'integration_spec.dart';
import 'lists_spec.dart';
import 'memory_spec.dart';
import 'obsidian_spec.dart';
import 'web_spec.dart';

/// The built-in integrations, in display order: one line per integration.
final builtInIntegrationSpecs = <IntegrationSpec>[
  calendarSpec,
  clipboardSpec,
  alarmsSpec,
  memorySpec,
  webSpec,
  obsidianSpec,
  bringSpec,
  listsSpec,
];
