import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Hands [text] to the app [androidPackage] via its share target.
typedef ShareToApp = Future<void> Function(String androidPackage, String text);

/// `ACTION_SEND` with `text/plain` directly to [androidPackage] (no share
/// sheet). Throws a `PortException` if the app cannot receive it.
Future<void> shareTextToApp(String androidPackage, String text) async {
  checkAndroidPackage(androidPackage);
  try {
    await AndroidIntent(
      action: 'action_send',
      package: androidPackage,
      type: 'text/plain',
      arguments: {'android.intent.extra.TEXT': text},
      flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
    ).launch();
  } on PlatformException {
    throw const PortException(
      PortErrorKind.unavailable,
      'Die App nimmt keinen geteilten Text an.',
    );
  } on UnsupportedError {
    throw const PortException(
      PortErrorKind.unsupported,
      'Teilen an Apps geht hier nicht.',
    );
  }
}
