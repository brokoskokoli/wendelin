import 'dart:io';

/// Total RAM of the device in bytes, or `null` if unknown (not Android,
/// file not readable). Reads `MemTotal` from `/proc/meminfo`, the same
/// value as `ActivityManager.MemoryInfo.totalMem`, without a platform
/// channel. [read] is injectable for tests.
Future<int?> deviceTotalMemory({Future<String> Function()? read}) async {
  if (read == null && !Platform.isAndroid) return null;
  try {
    final text = await (read ?? () => File('/proc/meminfo').readAsString())();
    return parseMemTotal(text);
  } on FileSystemException {
    return null;
  }
}

/// `MemTotal` of a `/proc/meminfo` text in bytes, or `null`.
int? parseMemTotal(String meminfo) {
  final m = RegExp(
    r'^MemTotal:\s+(\d+)\s*kB',
    multiLine: true,
  ).firstMatch(meminfo);
  final kb = m == null ? null : int.tryParse(m[1]!);
  return kb == null ? null : kb * 1024;
}

/// Below this total RAM the onboarding suggests Whisper base instead of
/// small (WP33). The kernel reports a little less than the marketed size
/// (a „4 GB“ phone shows about 3.6–3.8 GiB), so the line sits at 3.5 GiB:
/// phones with 4 GB get small, phones with 3 GB or less base.
const lowMemoryBytes = 3584 * 1024 * 1024;

/// Whether [totalBytes] counts as little memory (`null` = unknown = no).
bool isLowMemory(int? totalBytes) =>
    totalBytes != null && totalBytes < lowMemoryBytes;
