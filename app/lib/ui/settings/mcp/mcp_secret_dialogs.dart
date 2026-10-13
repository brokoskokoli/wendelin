import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/mcp/mcp_source.dart';
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
        check.ok ? 'Angemeldet' : 'Prüfung: ${mcpCheckText(check)}',
      );
    }
  } on McpSignInException catch (e) {
    if (context.mounted) showHint(context, e.message);
  } on McpException catch (e) {
    if (context.mounted) {
      showHint(context, 'Anmeldung fehlgeschlagen: ${e.message}');
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
        '„${server.config.name}“: auf der Serverseite anmelden',
      );
    case McpBearerAuth(:final secretRef):
      await askSecret(context, ref, server, secretRef, 'Bearer-Token');
    case McpHeadersAuth(:final secretRefsByHeader):
      for (final MapEntry(key: header, value: secretRef)
          in secretRefsByHeader.entries) {
        if (!context.mounted) return;
        await askSecret(context, ref, server, secretRef, 'Wert für $header');
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
    action: 'Speichern',
    obscure: true,
  );
  if (value == null || value.isEmpty) return;
  await source.setSecret(server.config.id, secretRef, value);
  if (context.mounted) showHint(context, 'Gespeichert');
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
        content: TextField(
          key: const ValueKey('mcpDialogField'),
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: obscure ? 1 : maxLines,
          style: WText.body,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
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
