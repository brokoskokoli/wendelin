import 'package:flutter/material.dart';

import '../design/design.dart';

/// One check stage: symbol, name, result and optional reason.
class StageLine extends StatelessWidget {
  /// Creates the line.
  const StageLine({
    super.key,
    required this.label,
    required this.result,
    required this.status,
    this.detail,
  });

  /// Name of the stage.
  final String label;

  /// Result in words („bestanden“).
  final String result;

  /// Short reason.
  final String? detail;

  /// Symbol; `null` for stages that are only logged.
  final CheckStatus? status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WSpace.l,
      vertical: WSpace.s,
    ),
    child: Row(
      spacing: WSpace.m,
      children: [
        if (status != null)
          CheckStatusIcon(status!, size: WSize.statusIconSmall)
        else
          const SizedBox.square(dimension: WSize.statusIconSmall),
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label · $result', style: WText.body),
                if (detail != null) Text(detail!, style: WText.caption),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
