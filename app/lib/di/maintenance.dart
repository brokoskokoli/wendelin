import 'package:wendelin_storage/wendelin_storage.dart';

import 'preferences.dart';

/// Housekeeping before the first frame: deletes logs and conversations
/// older than [retentionDays] and API keys no profile refers to any more.
Future<void> startupMaintenance({
  required WendelinStorage storage,
  required SecretStore secrets,
  required int retentionDays,
}) async {
  await purgeExpired(storage, retentionDays);
  await removeOrphanProviderSecrets(storage, secrets);
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
