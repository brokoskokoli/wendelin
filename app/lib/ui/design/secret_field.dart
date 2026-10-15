import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Input for a secret (API key, password, token): masked, offered to the
/// password manager (Android autofill, [autofillHints]) and kept out of
/// the keyboard's learning ([TextField.autocorrect],
/// [TextField.enableIMEPersonalizedLearning]; the masked field already has
/// no suggestions).
///
/// Deliberately neither `enableSuggestions: false` nor
/// `TextInputType.visiblePassword`: with `obscureText` the engine ignores
/// `enableSuggestions` anyway, and `visiblePassword` only picks a keyboard
/// variant. Password managers most likely offered nothing because nothing
/// was ever saved: without the autofill commit ([finishAutofill] after
/// saving, [AutofillGroup] with `onDisposeAction: cancel` elsewhere) the
/// manager has nothing to offer (WP65).
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
    this.autofocus = false,
  });

  /// Tells the password manager that the login is done (save prompt).
  static void finishAutofill() => autofillFinisher();

  /// What [finishAutofill] calls; tests replace it to observe the order.
  @visibleForTesting
  static void Function() autofillFinisher = TextInput.finishAutofillContext;

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

  /// Whether the field takes the focus when it appears (dialogs).
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: mono ? WText.mono : WText.body,
    autofocus: autofocus,
    obscureText: true,
    autocorrect: false,
    enableIMEPersonalizedLearning: false,
    autofillHints: autofillHints,
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
    ),
  );
}
