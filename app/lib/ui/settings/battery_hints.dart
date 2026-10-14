import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/battery_platform.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Power management of the device right now (WP56).
final batteryStatusProvider = FutureProvider<BatteryStatus>(
  (ref) => ref.watch(batteryPlatformProvider).status(),
);

/// Checklist per manufacturer: Android cannot read these settings, so the
/// text is a to-do list, not a status. Extend the table for more vendors.
const vendorChecklists = <String, (String, String)>{
  'xiaomi': (
    'Xiaomi / HyperOS / MIUI',
    'Schalte für Wendelin „Autostart“ ein und stelle den Akkusparer für '
        'Wendelin auf „Keine Einschränkungen“ '
        '(Einstellungen → Apps → Berechtigungen → Autostart; '
        'Einstellungen → Apps → Wendelin → Akkusparer).',
  ),
  'samsung': (
    'Samsung',
    'Nimm Wendelin aus „Schlafende Apps“ heraus und stelle den Akku für '
        'Wendelin auf „Nicht eingeschränkt“ '
        '(Einstellungen → Akku → Hintergrundnutzungsgrenzen).',
  ),
  'oneplus': (
    'OnePlus',
    'Erlaube Wendelin den Autostart und stelle die Akku-Optimierung für '
        'Wendelin auf „Nicht optimieren“ '
        '(Einstellungen → Apps → Wendelin → Akku).',
  ),
  'huawei': (
    'Huawei / Honor',
    'Stelle „App-Start“ für Wendelin auf „Manuell verwalten“ und erlaube '
        'Autostart, Zweitstart und Hintergrundaktivität.',
  ),
};

/// Hint when Android optimizes the battery use of Wendelin.
const batteryOptimizedTitle = 'Akku-Optimierung aktiv';

/// Explains why the optimization matters for the assistant.
const batteryOptimizedDetail =
    'Android kann Wendelin im Hintergrund beenden. Nach längerer Pause '
    'öffnet die Power-Taste den Assistenten dann womöglich nicht, bis du '
    'die App einmal geöffnet hast.';

/// Title when the standby bucket limits background starts.
String standbyBucketTitle(StandbyBucket bucket) => switch (bucket) {
  StandbyBucket.restricted => 'App-Standby: eingeschränkt',
  _ => 'App-Standby: selten genutzt',
};

/// Detail when the standby bucket limits background starts.
const standbyBucketDetail =
    'Android verzögert Starts im Hintergrund für selten genutzte Apps. '
    'Öffne Wendelin ab und zu oder erlaube „Keine Einschränkung“.';

/// Battery hints for the assistant: optimization status with a button for
/// the exemption, the standby bucket when it limits starts, and the
/// checklist of the manufacturer (with a link if its page can be opened).
/// Shows nothing where nothing applies (stock Android without limits).
class BatteryHints extends ConsumerStatefulWidget {
  /// Creates the hints.
  const BatteryHints({super.key});

  @override
  ConsumerState<BatteryHints> createState() => _BatteryHintsState();
}

class _BatteryHintsState extends ConsumerState<BatteryHints> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the system dialog or settings: check again.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(batteryStatusProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _open(Future<bool> Function() action) async {
    final opened = await action();
    if (!opened && mounted) {
      showHint(context, 'Die Systemeinstellungen ließen sich nicht öffnen.');
    }
  }

  Widget _action(String label, Future<bool> Function() action) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: () => unawaited(_open(action)),
      style: TextButton.styleFrom(
        foregroundColor: WColors.link,
        minimumSize: const Size(WSize.touchMin, WSize.touchMin),
      ),
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(batteryStatusProvider).value;
    if (status == null || !status.hasHints) return const SizedBox.shrink();
    final platform = ref.read(batteryPlatformProvider);
    final checklist = vendorChecklists[status.vendor];
    final bucket = status.bucket;
    return SettingsSection(
      title: 'Zuverlässig öffnen',
      children: [
        if (!status.ignoringOptimizations) ...[
          const SectionCard(
            children: [
              SettingsRow(
                key: ValueKey('batteryOptimized'),
                title: batteryOptimizedTitle,
                detail: batteryOptimizedDetail,
              ),
            ],
          ),
          _action(
            'Keine Einschränkung erlauben',
            platform.requestIgnoreOptimizations,
          ),
        ],
        if (bucket != null && bucket.limited)
          SectionCard(
            children: [
              SettingsRow(
                key: const ValueKey('standbyBucket'),
                title: standbyBucketTitle(bucket),
                detail: standbyBucketDetail,
              ),
            ],
          ),
        if (checklist != null) ...[
          SectionCard(
            children: [
              SettingsRow(
                key: const ValueKey('vendorChecklist'),
                title: checklist.$1,
                detail: checklist.$2,
              ),
            ],
          ),
          if (status.vendorSettings)
            _action(
              'Einstellungen des Herstellers öffnen',
              platform.openVendorSettings,
            )
          else
            _action('Akku-Einstellungen öffnen', platform.openBatterySettings),
          Text(
            'Android lässt diese Einstellungen nicht auslesen. '
            'Das ist eine Checkliste, kein Status.',
            style: WText.caption,
          ),
        ],
      ],
    );
  }
}
