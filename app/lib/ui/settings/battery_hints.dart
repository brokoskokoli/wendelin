import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../platform/battery_platform.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Power management of the device right now (WP56).
final batteryStatusProvider = FutureProvider<BatteryStatus>(
  (ref) => ref.watch(batteryPlatformProvider).status(),
);

/// Checklist per manufacturer: Android cannot read these settings, so the
/// text is a to-do list, not a status. Extend the table for more vendors.
Map<String, (String, String)> vendorChecklists(AppLocalizations l) => {
  'xiaomi': (l.batteryXiaomiTitle, l.batteryXiaomiBody),
  'samsung': (l.batterySamsungTitle, l.batterySamsungBody),
  'oneplus': (l.batteryOnePlusTitle, l.batteryOnePlusBody),
  'huawei': (l.batteryHuaweiTitle, l.batteryHuaweiBody),
};

/// Title when the standby bucket limits background starts.
String standbyBucketTitle(AppLocalizations l, StandbyBucket bucket) =>
    switch (bucket) {
      StandbyBucket.restricted => l.batteryStandbyRestricted,
      _ => l.batteryStandbyRare,
    };

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
      showHint(context, context.l10n.batterySettingsNotOpened);
    }
  }

  Widget _action(String label, Future<bool> Function() action) =>
      LinkButton(label, onPressed: () => unawaited(_open(action)));

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(batteryStatusProvider).value;
    if (status == null || !status.hasHints) return const SizedBox.shrink();
    final platform = ref.read(batteryPlatformProvider);
    final checklist = vendorChecklists(context.l10n)[status.vendor];
    final bucket = status.bucket;
    return SettingsSection(
      title: context.l10n.batteryReliable,
      children: [
        if (!status.ignoringOptimizations) ...[
          SectionCard(
            children: [
              SettingsRow(
                key: const ValueKey('batteryOptimized'),
                title: context.l10n.batteryOptimizedTitle,
                detail: context.l10n.batteryOptimizedDetail,
              ),
            ],
          ),
          _action(
            context.l10n.batteryAllow,
            platform.requestIgnoreOptimizations,
          ),
        ],
        if (bucket != null && bucket.limited)
          SectionCard(
            children: [
              SettingsRow(
                key: const ValueKey('standbyBucket'),
                title: standbyBucketTitle(context.l10n, bucket),
                detail: context.l10n.batteryStandbyDetail,
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
              context.l10n.batteryVendorSettings,
              platform.openVendorSettings,
            )
          else
            _action(
              context.l10n.batteryOpenSettings,
              platform.openBatterySettings,
            ),
          InfoBox(context.l10n.batteryChecklistNote),
        ],
      ],
    );
  }
}
