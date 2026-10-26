import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/app_requirements.dart';
import '../../di/integration_specs.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../routes.dart';
import '../screens/labels.dart';
import 'integration_detail_screen.dart';
import 'mcp/mcp_server_detail_screen.dart';
import 'reconnect_text.dart';
import 'settings_page.dart';
import 'settings_routes.dart';

/// Settings → Integrationen (docs/design/screens/integrationen): every
/// integration with its state and switch. Switching one on asks for its
/// permission only now, after an explanation. User-defined integrations
/// (MCP servers, HTTP tools; ADR 0012) follow in their own section.
class IntegrationsScreen extends ConsumerWidget {
  /// Creates the screen.
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(toolRegistryProvider);
    final sync = ref.watch(userIntegrationSyncProvider);
    return SettingsPage(
      title: context.l10n.areaIntegrations,
      intro: context.l10n.integrationsIntro,
      children: [
        _OnChanges(
          streams: [registry.changes, sync.changes],
          builder: (context) {
            final infos = selectableIntegrations(registry);
            final builtIn = [
              for (final i in infos)
                if (sync.kindOf(i.id) == null) i,
            ];
            final own = [
              for (final i in infos)
                if (sync.kindOf(i.id) != null) i,
            ];
            final rejected = sync.rejected;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WSpace.l18,
              children: [
                SectionCard(
                  children: [
                    for (final info in displayOrder(builtIn))
                      IntegrationRow(info, openDetail: true),
                  ],
                ),
                if (own.isNotEmpty || rejected.isNotEmpty)
                  SettingsSection(
                    title: context.l10n.integrationsOwn,
                    children: [
                      for (final info in displayOrder(own))
                        IntegrationRow(
                          info,
                          openDetail: true,
                          kind: sync.kindOf(info.id),
                        ),
                      for (final MapEntry(key: id, value: reason)
                          in rejected.entries)
                        SettingsRow(
                          title: id,
                          detail: context.l10n.integrationsRejected(reason),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
        Row(
          spacing: WSpace.m,
          children: [
            for (final (label, route) in [
              (context.l10n.integrationsAddMcp, AppRoutes.mcpServers),
              (context.l10n.integrationsAddHttp, AppRoutes.httpTools),
            ])
              Expanded(
                child: WideButton(
                  label,
                  onPressed: () => Navigator.of(context).pushNamed(route),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Rebuilds [builder] whenever one of [streams] emits.
class _OnChanges extends StatelessWidget {
  const _OnChanges({required this.streams, required this.builder});

  final List<Stream<void>> streams;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => streams.fold<WidgetBuilder>(
    builder,
    (inner, stream) =>
        (context) => StreamBuilder<void>(
          stream: stream,
          builder: (context, _) => inner(context),
        ),
  )(context);
}

/// One integration as [IntegrationTile] with switch, „Einrichten“, store
/// link and (with [openDetail]) its detail page. Used by the settings and
/// the onboarding.
class IntegrationRow extends ConsumerWidget {
  /// Creates the row for [info].
  const IntegrationRow(
    this.info, {
    super.key,
    this.openDetail = false,
    this.kind,
  });

  /// The integration.
  final IntegrationInfo info;

  /// Tapping the row opens [IntegrationDetailScreen].
  final bool openDetail;

  /// Kind of a user-defined integration (badge).
  final UserIntegrationKind? kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeUrl = info.status == IntegrationStatus.unavailable
        ? info.availability.storeUrl
        : null;
    final retry = info.status == IntegrationStatus.error
        ? _spec(ref, info.id)?.retry
        : null;
    final tile = IntegrationTile(
      name: info.integration.displayName,
      icon: kind == null ? integrationIcon(info.id) : WIcons.globe,
      status: info.status,
      detail: integrationDetail(
        context.l10n,
        info,
        appHint: _appHint(context, ref),
      ),
      sensitive: info.integration.sensitive,
      kind: kind?.badge,
      minPrivacy: info.integration.sensitive
          ? ref.watch(toolPrefsProvider).sensitiveMinimum
          : null,
      onToggle: (on) => unawaited(switchIntegration(context, ref, info.id, on)),
      actionLabel: retry == null ? null : context.l10n.retry,
      onAction: retry == null
          ? () => unawaited(setUpIntegration(context, ref, info.id))
          : () => unawaited(_retry(context, retry)),
      onStore: storeUrl == null
          ? null
          : () => unawaited(openStore(context, ref, storeUrl)),
    );
    if (!openDetail) return tile;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => switch (kind) {
            UserIntegrationKind.mcp => McpServerDetailScreen.forIntegration(
              info.id,
            ),
            _ => IntegrationDetailScreen(info.id),
          },
        ),
      ),
      child: tile,
    );
  }

  /// „Erneut versuchen“: runs the spec's retry and shows the outcome.
  Future<void> _retry(BuildContext context, IntegrationRetry retry) async {
    final error = await retry.run(unwrapIntegration(info.integration));
    if (context.mounted) {
      showHint(
        context,
        reconnectHint(
          context.l10n,
          error,
          context.l10n.integrationsReachable(info.integration.displayName),
        ),
      );
    }
  }

  /// Hint of an optional app that is missing (e.g. Obsidian links).
  String? _appHint(BuildContext context, WidgetRef ref) {
    final app = _spec(ref, info.id)?.requiredApp;
    if (app == null || app.needed) return null;
    final installed = ref.read(installedAppsProvider)[app.androidPackage];
    if (installed != false) return null;
    final l = context.l10n;
    return switch (app.androidPackage) {
      'ch.publisheria.bring' => l.integrationsHintBring,
      'md.obsidian' => l.integrationsHintObsidian,
      'com.spotify.music' => l.integrationsHintSpotify,
      _ => app.missingHint,
    };
  }
}

/// Integrations the user can choose on this device: those of other
/// platforms are left out (concept: „Integrationen auswählen“), those
/// with a missing app stay (greyed out).
List<IntegrationInfo> selectableIntegrations(ToolRegistry registry) {
  final platform = registry.platform;
  return [
    for (final info in registry.integrations)
      if (platform == null || info.integration.platforms.contains(platform))
        info,
  ];
}

/// Integrations for display: usable ones first, unavailable ones last
/// (as in the design), otherwise in registry order.
List<IntegrationInfo> displayOrder(List<IntegrationInfo> infos) => [
  for (final i in infos)
    if (i.status != IntegrationStatus.unavailable) i,
  for (final i in infos)
    if (i.status == IntegrationStatus.unavailable) i,
];

/// Reason of an unavailable integration in the app language (the reason of
/// a missing app is translated; others come as they are).
String? availabilityReason(AppLocalizations l, String? reason) =>
    reason == appMissingReason ? l.integrationsAppMissing : reason;

/// Second line of an integration tile. [appHint] is the hint of a missing
/// optional app.
String? integrationDetail(
  AppLocalizations l,
  IntegrationInfo info, {
  String? appHint,
}) {
  final tools = info.integration.tools.length;
  return switch (info.status) {
    // Switched on but the app is gone: paused, the switch stays.
    IntegrationStatus.unavailable when info.enabled => [
      ?availabilityReason(l, info.availability.reason),
      l.integrationsPaused,
    ].join(' · '),
    IntegrationStatus.unavailable => availabilityReason(
      l,
      info.availability.reason,
    ),
    IntegrationStatus.error => integrationErrorText(
      l,
      info.integration.id,
      info.error,
      info.errorKind,
    ),
    IntegrationStatus.setupRequired => [
      for (final step in info.integration.setup)
        if (info.setup.missingSteps.contains(step.id)) step.label,
    ].join(' · '),
    IntegrationStatus.active => [
      if (tools == 1) l.mcpLabelsOneTool else l.integrationsTools(tools),
      ?appHint,
    ].join(' · '),
    // „Verfügbar“ or „Nur an Provider ab …“ (design).
    IntegrationStatus.available => appHint,
  };
}

/// Opens the download page of a missing app; if no browser can open it,
/// the address is shown instead.
Future<void> openStore(BuildContext context, WidgetRef ref, String url) async {
  final launch = ref.read(urlLauncherProvider);
  try {
    await launch(Uri.parse(url));
  } on PortException {
    if (context.mounted) showHint(context, url);
  }
}

IntegrationSpec? _spec(WidgetRef ref, String id) =>
    ref.read(integrationSpecsProvider).where((s) => s.id == id).firstOrNull;

/// Switches [id] on or off. Before a permission request the user sees the
/// integration's explanation and can cancel.
Future<void> switchIntegration(
  BuildContext context,
  WidgetRef ref,
  String id,
  bool on,
) async {
  // Read everything before awaiting: the page may be gone afterwards.
  final activator = ref.read(integrationActivatorProvider);
  final rationale = _rationale(context, ref, id);
  if (on && rationale != null) {
    final ok = await confirm(
      context,
      title: context.l10n.integrationsPermission,
      message: rationale,
      yes: context.l10n.next,
    );
    if (!ok) return;
  }
  await activator.setEnabled(id, enabled: on);
}

/// „Einrichten“: asks for the permission again or opens the page where the
/// missing setup happens (lists, web search).
Future<void> setUpIntegration(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final registry = ref.read(toolRegistryProvider);
  final activator = ref.read(integrationActivatorProvider);
  final page = setupPageFor(id);
  if (page != null) {
    await Navigator.of(context).pushNamed(page);
    await registry.refresh(id);
    return;
  }
  final rationale = _rationale(context, ref, id);
  if (rationale != null) {
    final ok = await confirm(
      context,
      title: context.l10n.integrationsPermission2,
      message: rationale,
      yes: context.l10n.next,
    );
    if (!ok) return;
  }
  await activator.setUp(id);
}

/// Permission explanation of integration [id]: the translated text where
/// there is one, else the spec's own.
String? _rationale(BuildContext context, WidgetRef ref, String id) =>
    switch (id) {
      'calendar' => context.l10n.integrationsCalendarRationale,
      'media' => context.l10n.integrationsMediaRationale,
      'contacts' => context.l10n.integrationsContactsRationale,
      'location' => context.l10n.integrationsLocationRationale,
      _ => _spec(ref, id)?.permissionRationale,
    };
