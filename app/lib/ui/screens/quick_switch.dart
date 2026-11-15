import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';

/// Holding the chip for the platform long-press time ([kLongPressTimeout])
/// opens the switch: a short vibration (HapticFeedback follows the system
/// setting) and [onOpen] run together, there is no further waiting stage.
/// Letting go earlier or moving more than [kTouchSlop] cancels; letting go
/// after opening does nothing (WP94).
///
/// For screen readers a custom action opens [onOpen] directly.
class QuickSwitchTarget extends StatefulWidget {
  /// Creates the target around [child]; `onOpen == null` disables it.
  const QuickSwitchTarget({super.key, required this.child, this.onOpen});

  /// The chip.
  final Widget child;

  /// Opens the switch popup.
  final VoidCallback? onOpen;

  @override
  State<QuickSwitchTarget> createState() => _QuickSwitchTargetState();
}

class _QuickSwitchTargetState extends State<QuickSwitchTarget> {
  Timer? _timer;
  Offset? _down;

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _down = null;
  }

  void _start(PointerDownEvent e) {
    if (widget.onOpen == null) return;
    _cancel();
    _down = e.position;
    _timer = Timer(kLongPressTimeout, () {
      _cancel();
      final open = widget.onOpen;
      if (open == null) return;
      unawaited(HapticFeedback.mediumImpact());
      open();
    });
  }

  @override
  void didUpdateWidget(QuickSwitchTarget old) {
    super.didUpdateWidget(old);
    if (widget.onOpen == null) _cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.onOpen;
    final label = context.l10n.quickSwitchSemanticsAction;
    return Listener(
      onPointerDown: _start,
      onPointerMove: (e) {
        final d = _down;
        if (d != null && (e.position - d).distance > kTouchSlop) _cancel();
      },
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: Semantics(
        key: const ValueKey('quickSwitchTarget'),
        container: true,
        onLongPressHint: open == null ? null : label,
        onLongPress: open,
        customSemanticsActions: open == null
            ? null
            : {CustomSemanticsAction(label: label): open},
        child: widget.child,
      ),
    );
  }
}

/// Asks for the agent to switch to; returns its profile id or `null`.
Future<String?> showQuickSwitchSheet(
  BuildContext context, {
  required List<ProviderProfile> profiles,
  required String? currentId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: false,
  builder: (_) => QuickSwitchSheet(profiles: profiles, currentId: currentId),
);

/// Sheet with all set-up agents; the current one is marked. A tap on
/// another one is the confirmation (pops its id).
class QuickSwitchSheet extends StatelessWidget {
  /// Creates the sheet content.
  const QuickSwitchSheet({
    super.key,
    required this.profiles,
    required this.currentId,
  });

  /// All profiles.
  final List<ProviderProfile> profiles;

  /// Id of the active profile.
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WSpace.screen,
          WSpace.m14,
          WSpace.screen,
          WSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.m,
          children: [
            const SheetDragHandle(),
            Text(l.quickSwitchTitle, style: WText.cardTitle),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in profiles)
                      _Row(
                        profile: p,
                        current: p.id == currentId,
                        onTap: () => Navigator.of(context).pop(p.id),
                      ),
                  ],
                ),
              ),
            ),
            Text(l.quickSwitchHint, style: WText.caption),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.profile,
    required this.current,
    required this.onTap,
  });

  final ProviderProfile profile;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      button: true,
      selected: current,
      label: l.quickSwitchItemSemantics(
        profile.name,
        profile.privacy.labelOf(l),
      ),
      value: current ? l.quickSwitchCurrent : null,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: WSize.listRow),
          child: Row(
            spacing: WSpace.m,
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  style: WText.itemTitle.copyWith(
                    color: current ? WColors.accentLight : WColors.text,
                  ),
                ),
              ),
              PrivacyChip(profile.privacy),
              SizedBox(
                width: WSize.iconSmall,
                child: current
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        size: WSize.iconSmall,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
