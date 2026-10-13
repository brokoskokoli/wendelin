import 'package:wendelin_integrations/obsidian.dart';

import '../app_requirements.dart';
import '../vocabulary_provider.dart';
import 'integration_spec.dart';

/// Obsidian vault.
final obsidianSpec = IntegrationSpec(
  id: 'obsidian',
  // Device: SAF vault; until a folder is chosen (Einstellungen →
  // Obsidian) it shows „Einrichtung nötig“. Demo: in-memory vault.
  isSupported: (d) => d.ports.obsidian != null,
  // The vault is a folder; the app only opens notes (obsidian:// links).
  requiredApp: KnownApps.obsidian.optional(
    'Obsidian-App fehlt: Öffnen in Obsidian geht nicht',
  ),
  // Whether the speech correction put the title of a note path into the
  // current request (consumed once; WP33, B8).
  prepare: (ref) => ref.watch(correctedTitlesProvider).take,
  create: (d) {
    final o = d.ports.obsidian!;
    return ObsidianIntegration(
      o.vault,
      o.index,
      settings: o.settings,
      openUri: o.openUri,
      indexer: o.indexer,
      spokenCorrection: d.extra<bool Function(String)>('obsidian'),
    );
  },
);
