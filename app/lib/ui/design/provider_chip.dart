import 'package:flutter/widgets.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';
import 'check_status.dart';
import 'privacy_chip.dart';

/// Chip mit aktivem Provider/Modell, Datenschutzstufe und optionalem
/// Prüfstatus der TEE-Quittung (z. B. „◆ Phala · GLM klein ✓“).
class ProviderChip extends StatelessWidget {
  /// Erstellt einen Provider-Chip.
  const ProviderChip({
    super.key,
    required this.name,
    required this.level,
    this.status,
  });

  /// Anzeigename (Provider · Modell).
  final String name;

  /// Datenschutzstufe des Providers.
  final PrivacyLevel level;

  /// Prüfstatus der letzten Quittung; `null` blendet ihn aus.
  final CheckStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return PrivacyChip(
      level,
      label: name,
      trailing: s == null
          ? null
          : CheckStatusIcon(s, size: WSize.statusIconSmall),
      semanticLabel: [
        'Provider $name',
        'Datenschutzstufe ${level.label}',
        if (s != null) 'Quittung ${s.label}',
      ].join(', '),
    );
  }
}
