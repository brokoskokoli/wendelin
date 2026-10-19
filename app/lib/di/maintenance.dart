import 'package:flutter/foundation.dart' show debugPrint;
import 'package:wendelin_storage/wendelin_storage.dart';

import 'bring.dart' show SecretStoreBringSecrets;
import 'preferences.dart';

/// Housekeeping before the first frame: deletes logs and conversations
/// older than [retentionDays] and API keys no profile refers to any more.
Future<void> startupMaintenance({
  required WendelinStorage storage,
  required SecretStore secrets,
  required int retentionDays,
  void Function(String line)? log,
}) async {
  await purgeExpired(storage, retentionDays);
  await removeOrphanProviderSecrets(storage, secrets);
  await removeLegacyBringLogin(secrets, log: log);
}

/// WP107: deletes the Bring! e-mail and password of earlier versions at
/// every app start (independent of the demo mode and of any availability
/// check). A failure is not fatal but logged (error type only, no values).
Future<void> removeLegacyBringLogin(
  SecretStore secrets, {
  void Function(String line)? log,
}) async {
  try {
    await SecretStoreBringSecrets(secrets).removeLegacyLogin();
  } on Object catch (e) {
    (log ?? debugPrint)('Bring: legacy login not removed (${e.runtimeType})');
  }
}

/// Deletes `provider.*` secrets that no stored profile references (e.g.
/// left behind by an interrupted setup); returns the deleted keys.
Future<Set<String>> removeOrphanProviderSecrets(
  WendelinStorage storage,
  SecretStore secrets,
) async {
  final used = {
    for (final p in await storage.providerProfiles.list())
      ...p.authMethod.secretRefs,
  };
  final orphans = {
    for (final key in await secrets.listKeys())
      if (key.startsWith('provider.') && !used.contains(key)) key,
  };
  for (final key in orphans) {
    await secrets.delete(key);
  }
  return orphans;
}
