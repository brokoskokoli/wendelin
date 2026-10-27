import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/restricted_settings_platform.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// What the user tried to switch on.
enum RestrictedFeature {
  /// SMS permission (contacts integration, `SEND_SMS`).
  sms,

  /// Notification access (media integration, listener).
  notificationAccess,
}

/// Hint with steps and a button to the app info, shown under an integration
/// whose SMS permission / notification access is missing AND Android blocks
/// it as "restricted setting" (APK installed from a file, WP159).
///
/// The state is asked again when the widget appears or changes, when the
/// tool registry changes (after the permission request) and when the app
/// returns from the system settings. Android only marks the app as
/// restricted at the first blocked attempt, so the first check alone is not
/// enough. A normal refusal (op not `ignored`) shows nothing.
class RestrictedSettingsHint extends ConsumerStatefulWidget {
  /// Creates the hint for [feature].
  const RestrictedSettingsHint(this.feature, {super.key});

  /// The permission the integration needs.
  final RestrictedFeature feature;

  @override
  ConsumerState<RestrictedSettingsHint> createState() =>
      _RestrictedSettingsHintState();
}

class _RestrictedSettingsHintState extends ConsumerState<RestrictedSettingsHint>
    with WidgetsBindingObserver {
  bool _blocked = false;
  int _check = 0;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = ref.read(toolRegistryProvider).changes.listen((_) => _recheck());
    unawaited(_recheck());
  }

  @override
  void didUpdateWidget(RestrictedSettingsHint old) {
    super.didUpdateWidget(old);
    unawaited(_recheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_recheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<bool> _granted() async {
    final ports = ref.read(platformPortsProvider);
    return switch (widget.feature) {
      RestrictedFeature.sms => await ports.phone?.canSendSms() ?? true,
      RestrictedFeature.notificationAccess =>
        await ports.media?.hasSessionAccess() ?? true,
    };
  }

  /// Hint only if not granted AND restricted. The latest check wins.
  Future<void> _recheck() async {
    final platform = ref.read(restrictedSettingsPlatformProvider);
    final id = ++_check;
    final granted = await _granted();
    final restricted = granted ? false : (await platform.state()).restricted;
    if (!mounted || id != _check) return;
    if (restricted != _blocked) setState(() => _blocked = restricted);
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocked) return const SizedBox.shrink();
    final l = context.l10n;
    final what = switch (widget.feature) {
      RestrictedFeature.sms => l.restrictedSettingsWhatSms,
      RestrictedFeature.notificationAccess => l.restrictedSettingsWhatAccess,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WSpace.l18,
        vertical: WSpace.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WSpace.s,
        children: [
          Text(l.restrictedSettingsTitle, style: WText.label),
          Text(l.restrictedSettingsBody(what), style: WText.caption),
          Text(l.restrictedSettingsSteps, style: WText.caption),
          WideButton(
            l.restrictedSettingsOpenAppInfo,
            onPressed: () => unawaited(
              ref.read(restrictedSettingsPlatformProvider).openAppInfo(),
            ),
          ),
        ],
      ),
    );
  }
}
