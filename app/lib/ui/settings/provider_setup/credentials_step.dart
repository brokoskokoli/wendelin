import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../../di/provider_setup.dart';
import '../../design/design.dart';
import '../settings_page.dart';

/// Profile name; with [login] the password manager's user name.
Widget _nameField(TextEditingController name, {required bool login}) =>
    TextField(
      key: const ValueKey('providerName'),
      controller: name,
      style: WText.body,
      autofillHints: login ? const [AutofillHints.username] : null,
      decoration: const InputDecoration(labelText: 'Name'),
    );

Widget _baseUrlField(TextEditingController baseUrl) => TextField(
  controller: baseUrl,
  style: WText.body,
  keyboardType: TextInputType.url,
  decoration: const InputDecoration(labelText: 'Base-URL'),
);

/// Step 2: name, base URL and key of the provider, connection test.
List<Widget> credentialsStep({
  required ProviderSetupSession session,
  required TextEditingController name,
  required TextEditingController baseUrl,
  required TextEditingController apiKey,
  required bool busy,
  required bool editing,
  required Widget? failure,
  required VoidCallback onConnect,
  required VoidCallback onOtherTemplate,
  required void Function(String url) onOpenUrl,
}) {
  final t = session.template;
  return [
    // Name and key form one login for the password manager: the name
    // („Claude“) tells its entries apart, so a provider key is not
    // offered for Bring! or other secrets of the app.
    if (t.auth == TemplateAuth.none)
      _nameField(name, login: false)
    else
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.l18,
          children: [
            _nameField(name, login: true),
            if (t.type == ProviderType.openaiCompatible) _baseUrlField(baseUrl),
            SecretField(
              key: const ValueKey('apiKey'),
              controller: apiKey,
              label: t.auth == TemplateAuth.apiKey
                  ? 'API-Key'
                  : 'API-Key (optional)',
              helperText: session.keyStored
                  ? 'Key gespeichert – leer lassen behält ihn'
                  : null,
            ),
          ],
        ),
      ),
    if (t.auth == TemplateAuth.none && t.type == ProviderType.openaiCompatible)
      _baseUrlField(baseUrl),
    if (t.auth != TemplateAuth.none) ...[
      if (t.keyPageUrl case final url?)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => onOpenUrl(url),
            child: const Text('Key beim Anbieter erstellen'),
          ),
        ),
    ],
    ?failure,
    PrimaryButton(
      busy ? 'Teste …' : 'Verbindung testen',
      onPressed: busy ? null : onConnect,
    ),
    if (!editing) WideButton('Andere Vorlage', onPressed: onOtherTemplate),
  ];
}
