import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../agent/chat_entry.dart';
import '../../di/bring.dart';
import '../../di/providers.dart';
import '../design/design.dart';

/// Fallback card of a failed `bring__add_items` call (concept: „Offene
/// Fragen → Bring!“): „An Bring! senden“ shares the items with the Bring!
/// app. Shown only while the app is installed; otherwise nothing (the
/// failure is in the tool chip and the answer).
class BringShareCard extends ConsumerStatefulWidget {
  /// Creates the card for [entry] (with [ToolEntry.shareText]).
  const BringShareCard(this.entry, {super.key});

  /// The failed call.
  final ToolEntry entry;

  /// Whether [entry] gets this card (failed with share text).
  static bool applies(ToolEntry entry) =>
      entry.shareText != null && entry.phase == ToolPhase.failed;

  @override
  ConsumerState<BringShareCard> createState() => _BringShareCardState();
}

class _BringShareCardState extends ConsumerState<BringShareCard> {
  bool _installed = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final apps = ref.read(installedAppsProvider);
    bool installed;
    try {
      installed = await apps.check(BringAppFallback.androidPackage);
    } on Object {
      // Unknown counts as missing: the fallback is only offered when the
      // app is known to be there.
      installed = false;
    }
    if (mounted) setState(() => _installed = installed);
  }

  Future<void> _share() async {
    final share = ref.read(appShareProvider);
    try {
      await share(BringAppFallback.androidPackage, widget.entry.shareText!);
      if (mounted) setState(() => _sent = true);
    } on PortException catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.entry.shareText;
    if (!_installed || text == null) return const SizedBox.shrink();
    return SectionCard(
      dividers: false,
      padding: const EdgeInsets.all(WSpace.l),
      spacing: WSpace.m,
      children: [
        Row(
          spacing: WSpace.m,
          children: [
            const WIcon(WIcons.cart),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.xxs,
                children: [
                  Text('Bring! nicht erreichbar', style: WText.label),
                  Text(text.split('\n').join(', '), style: WText.detail),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton(
            onPressed: _sent ? null : () => unawaited(_share()),
            child: Text(_sent ? 'An Bring! gesendet' : 'An Bring! senden'),
          ),
        ),
      ],
    );
  }
}
