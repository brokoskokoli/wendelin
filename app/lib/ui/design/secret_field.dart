import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Input for a secret (API key, password, token): masked, offered to the
/// password manager (Android autofill, [autofillHints]) and kept out of
/// the keyboard's suggestions and learning ([TextField.enableSuggestions],
/// [TextField.autocorrect], [TextField.enableIMEPersonalizedLearning]).
///
/// A stored secret is never shown again: the screen says that one is
/// stored ([helperText]) and the field only replaces it. Several fields of
/// one login (e-mail and password) belong in one [AutofillGroup].
class SecretField extends StatelessWidget {
  /// Creates the field.
  const SecretField({
    super.key,
    required this.label,
    this.controller,
    this.onChanged,
    this.helperText,
    this.autofillHints = passwordHints,
    this.mono = false,
  });

  /// Autofill hint of a password, key or token.
  static const passwordHints = [AutofillHints.password];

  /// Label.
  final String label;

  /// Text controller (or [onChanged]).
  final TextEditingController? controller;

  /// Called on every change.
  final ValueChanged<String>? onChanged;

  /// Hint below the field, e.g. that a secret is stored.
  final String? helperText;

  /// Hints for the password manager.
  final List<String> autofillHints;

  /// Text in mono (technical values such as header values).
  final bool mono;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: mono ? WText.mono : WText.body,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    keyboardType: TextInputType.visiblePassword,
    autofillHints: autofillHints,
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
    ),
  );
}
