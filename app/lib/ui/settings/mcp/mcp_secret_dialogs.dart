import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'mcp_labels.dart';

/// OAuth login of [server]; shows a hint if it fails (no browser, denied,
/// aborted).
Future<void> signInMcp(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
) async {
  final source = ref.read(mcpServerSourceProvider);
  try {
    final check = await source.signIn(server.config.id);
    if (context.mounted) {
      showHint(
        context,
        check.ok
            ? context.l10n.mcpSecretSignedIn
            : context.l10n.mcpSecretCheck(mcpCheckText(context.l10n, check)),
      );
    }
  } on McpSignInException catch (e) {
    if (context.mounted) showHint(context, e.message);
  } on McpException catch (e) {
    if (context.mounted) {
      showHint(context, context.l10n.mcpSecretSignInFailed(e.message));
    }
  }
}

/// Asks for the secrets an imported [server] needs (token, header values);
/// an OAuth server gets a hint to log in on its page.
Future<void> askSecrets(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
) async {
  switch (server.config.auth) {
    case McpNoAuth():
      return;
    case McpOAuth():
      showHint(
        context,
        context.l10n.mcpSecretSignInOnServer(server.config.name),
      );
    case McpBearerAuth(:final secretRef):
      await askSecret(
        context,
        ref,
        server,
        secretRef,
        context.l10n.mcpDetailBearer,
      );
    case McpHeadersAuth(:final secretRefsByHeader):
      for (final MapEntry(key: header, value: secretRef)
          in secretRefsByHeader.entries) {
        if (!context.mounted) return;
        await askSecret(
          context,
          ref,
          server,
          secretRef,
          context.l10n.mcpDetailValueFor(header),
        );
      }
  }
}

/// Asks for one secret of [server] (masked, never shown again) and stores
/// it under [secretRef].
Future<void> askSecret(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
  String secretRef,
  String label,
) async {
  final source = ref.read(mcpServerSourceProvider);
  final value = await askText(
    context,
    title: server.config.name,
    label: label,
    action: context.l10n.save,
    obscure: true,
  );
  if (value == null || value.isEmpty) return;
  await source.setSecret(server.config.id, secretRef, value);
  if (context.mounted) showHint(context, context.l10n.mcpSecretSaved);
}

/// Dialog with one text field; `null` if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  bool obscure = false,
  int maxLines = 1,
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WColors.surface,
        title: Text(title, style: WText.label),
        content: obscure
            ? AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: SecretField(
                  key: const ValueKey('mcpDialogField'),
                  controller: controller,
                  label: label,
                  autofocus: true,
                ),
              )
            : TextField(
                key: const ValueKey('mcpDialogField'),
                controller: controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: maxLines,
                style: WText.body,
                decoration: InputDecoration(labelText: label),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              // Commit only on save, not on cancel.
              if (obscure) SecretField.finishAutofill();
              Navigator.of(context).pop(controller.text);
            },
            child: Text(action),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

/// Runs [step]; an [McpException] becomes a hint.
Future<void> guardMcp(
  BuildContext context,
  Future<void> Function() step,
) async {
  try {
    await step();
  } on McpException catch (e) {
    if (context.mounted) showHint(context, e.message);
  }
}
