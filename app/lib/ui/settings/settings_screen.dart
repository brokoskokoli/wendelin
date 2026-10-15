import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../design/design.dart';
import '../routes.dart';
import 'settings_page.dart';

/// Settings overview: one row per area (concept: „Einstellungen“). Routing,
/// MCP servers and HTTP tools open placeholder pages until WP26–WP28.
class SettingsScreen extends ConsumerWidget {
  /// Creates the overview.
  const SettingsScreen({super.key});

  /// Areas in display order: title, detail, route.
  static const areas = [
    ('Provider', 'Profile, Standard, Budget', AppRoutes.providers),
    ('Routing', 'Regeln, Testfeld, Import und Export', AppRoutes.routing),
    (
      'Integrationen',
      'Was Wendelin darf, Tools, Risikostufen',
      AppRoutes.integrations,
    ),
    ('MCP-Server', 'Server, Anmeldung, Status, Tools', AppRoutes.mcpServers),
    ('HTTP-Tools', 'Eigene Tools definieren und testen', AppRoutes.httpTools),
    (
      'Datenschutz und Logs',
      'Aufbewahrung, Prüfprotokoll, Export',
      AppRoutes.privacy,
    ),
    ('Kosten', 'Heute und im Monat je Provider', AppRoutes.costs),
    (
      'Assistent',
      'Standard-Assistent, dein Name, Persönlichkeit',
      AppRoutes.assistant,
    ),
    ('Sprache', 'Spracherkennung, Stimme, Tempo', AppRoutes.voice),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsPage(
    title: 'Einstellungen',
    children: [
      SectionCard(
        children: [
          for (final (title, detail, route) in areas)
            SettingsRow(
              title: title,
              detail: detail,
              onTap: () => Navigator.of(context).pushNamed(route),
            ),
        ],
      ),
      if (kDebugMode) const _Development(),
    ],
  );
}

class _Development extends ConsumerWidget {
  const _Development();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSection(
    title: 'Entwicklung',
    children: [
      SettingsRow(
        title: 'Demo-Modus (ohne Provider)',
        trailing: WSwitch(
          value: ref.watch(demoModeProvider),
          semanticLabel: 'Demo-Modus',
          onChanged: (on) =>
              unawaited(ref.read(demoModeProvider.notifier).set(enabled: on)),
        ),
      ),
      SettingsRow(
        title: 'Design-Galerie',
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.gallery),
      ),
    ],
  );
}
