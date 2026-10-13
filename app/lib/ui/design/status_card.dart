import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'check_status.dart';
import 'section_card.dart';

/// Result of a check as a card: [CheckStatusIcon] (colour + shape), a
/// title and an optional detail line, with an optional [action] at the
/// end (or below the text with [actionBelow], for long labels). Read out
/// as one element and announced when it appears.
class StatusCard extends StatelessWidget {
  /// Creates the card.
  const StatusCard({
    super.key,
    required this.status,
    required this.title,
    this.detail,
    this.action,
    this.actionBelow = false,
  });

  /// Status (ok, pending, failed).
  final CheckStatus status;

  /// Main line, e.g. „Verbindung steht“.
  final String title;

  /// Second line.
  final String? detail;

  /// Button at the end (e.g. „Erlauben“).
  final Widget? action;

  /// Puts [action] below the text, aligned to its end.
  final bool actionBelow;

  @override
  Widget build(BuildContext context) => SectionCard(
    children: [
      Semantics(
        liveRegion: true,
        container: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WSpace.l,
            vertical: WSpace.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: WSpace.s,
            children: [
              Row(
                spacing: WSpace.m,
                children: [
                  CheckStatusIcon(status),
                  Expanded(
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: WSpace.xxs,
                        children: [
                          Text(title, style: WText.label),
                          if (detail case final d?)
                            Text(d, style: WText.detail),
                        ],
                      ),
                    ),
                  ),
                  if (!actionBelow) ?action,
                ],
              ),
              if (actionBelow) ?action,
            ],
          ),
        ),
      ),
    ],
  );
}
