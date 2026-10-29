import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/developer_mode.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../routes.dart';
import 'dev_archive_section.dart';
import 'settings_page.dart';

/// Settings overview: one row per area (concept: „Einstellungen“). MCP servers
/// and HTTP tools are reached via „Integrationen“ only, routing via
/// „Provider“ (routes stay).
class SettingsScreen extends ConsumerWidget {
  /// Creates the overview.
  const SettingsScreen({super.key});

  /// Areas in display order: title, detail, route.
  static List<(String, String, String)> areas(AppLocalizations l) => [
    (l.areaProvider, l.areaProviderDetail, AppRoutes.providers),
    (l.areaIntegrations, l.areaIntegrationsDetail, AppRoutes.integrations),
    (l.areaPrivacy, l.areaPrivacyDetail, AppRoutes.privacy),
    (l.areaCosts, l.areaCostsDetail, AppRoutes.costs),
    (l.areaAssistant, l.areaAssistantDetail, AppRoutes.assistant),
    (l.areaSpeech, l.areaSpeechDetail, AppRoutes.voice),
    (l.areaWakeWord, l.areaWakeWordDetail, AppRoutes.wakeWord),
    (l.stationTitle, l.stationSettingsDetail, AppRoutes.station),
    (l.appLanguageTitle, l.appLanguageDetail, AppRoutes.appLanguage),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SettingsPage(
      title: l.settingsTitle,
      children: [
        SectionCard(
          children: [
            for (final (title, detail, route) in areas(l))
              SettingsRow(
                title: title,
                detail: detail,
                onTap: () => Navigator.of(context).pushNamed(route),
              ),
          ],
        ),
        if (ref.watch(developerModeProvider)) ...[
          Padding(
            padding: const EdgeInsets.only(top: WSpace.m),
            child: Text(l.developerModeActiveHint, style: WText.detail),
          ),
          const DevArchiveSection(),
        ],
        if (kDebugMode) const _Development(),
      ],
    );
  }
}

class _Development extends ConsumerWidget {
  const _Development();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SettingsSection(
      title: l.devSection,
      children: [
        SettingsRow(
          title: l.devDemoMode,
          trailing: WSwitch(
            value: ref.watch(demoModeProvider),
            semanticLabel: l.devDemoModeLabel,
            onChanged: (on) =>
                unawaited(ref.read(demoModeProvider.notifier).set(enabled: on)),
          ),
        ),
        SettingsRow(
          title: l.devGallery,
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.gallery),
        ),
      ],
    );
  }
}
