import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';

/// WP82: the GPU check mode used to be one global setting (`tee.gpuCheck`).
/// It is now part of each TEE profile (`options.gpuCheck`). Copies the old
/// value to every TEE profile that has none yet and removes the old
/// setting; a no-op without the old setting. Never throws.
Future<void> migrateGlobalGpuCheck(
  SettingsRepository settings,
  ProviderProfileRepository profiles,
) async {
  try {
    final old = await settings.get(AppSettings.legacyGpuCheck);
    if (old == null) return;
    final mode = GpuCheckMode.values.asNameMap()[old] ?? GpuCheckMode.off;
    for (final p in await profiles.list()) {
      if (!needsAttestation(p) || p.options.containsKey(gpuCheckOption)) {
        continue;
      }
      await profiles.save(
        p.copyWith(options: {...p.options, gpuCheckOption: mode.name}),
      );
    }
    await settings.remove(AppSettings.legacyGpuCheck);
  } on Object {
    // Try again at the next start; the profiles then keep the default (off).
  }
}
