import 'dart:convert';

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Applies a change to the draft and rebuilds the editor (clears a shown
/// test result).
typedef DraftEdit = void Function(void Function() change);

/// Padding of a form field inside a [SectionCard].
class EditorField extends StatelessWidget {
  /// Creates the padding around [child].
  const EditorField({super.key, required this.child});

  /// The field.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WSpace.l,
      vertical: WSpace.s,
    ),
    child: child,
  );
}

/// JSON with two-space indentation.
String prettyJson(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);
