import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Names of MCP servers and tools in the tool system.
///
/// - Integration id `mcp_<slug>`; the slug is derived from the server name
///   (only `[a-z0-9]`, umlauts transliterated, at most [maxSlug]
///   characters, unique among the given ones) and stored in the config, so
///   it stays stable.
/// - Tool names `mcp_<slug>__<tool>` with at most [maxToolName] characters
///   (limit of the provider APIs). A tool name that contains characters the
///   APIs refuse, or is too long, is shortened and gets `_` plus a short
///   hash of the original name: the mapping depends only on the original
///   name (stable) and different originals do not collide.
abstract final class McpNaming {
  /// Longest slug.
  static const maxSlug = 16;

  /// Longest tool name (provider APIs).
  static const maxToolName = 64;

  /// Hex characters of the hash suffix.
  static const hashLength = 6;

  static const _transliterate = {
    'ä': 'ae',
    'ö': 'oe',
    'ü': 'ue',
    'ß': 'ss',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ç': 'c',
    'ñ': 'n',
    'ó': 'o',
    'ô': 'o',
    'í': 'i',
    'ú': 'u',
  };

  /// A slug for the server [name] that is not in [taken].
  static String slugFor(String name, {Set<String> taken = const {}}) {
    final buffer = StringBuffer();
    for (final rune in name.toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      final mapped = _transliterate[c] ?? c;
      for (final m in mapped.codeUnits) {
        if ((m >= 0x61 && m <= 0x7a) || (m >= 0x30 && m <= 0x39)) {
          buffer.writeCharCode(m);
        }
      }
    }
    var base = buffer.toString();
    if (base.isEmpty) base = 'server';
    if (base.length > maxSlug) base = base.substring(0, maxSlug);
    if (!taken.contains(base)) return base;
    for (var n = 2; ; n++) {
      final suffix = '$n';
      final candidate =
          '${base.length + suffix.length > maxSlug ? base.substring(0, maxSlug - suffix.length) : base}$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// Prefix of all tool names of the server with [slug].
  static String prefix(String slug) => 'mcp_${slug}__';

  /// Tool names for the MCP tool names [tools] of the server [slug]:
  /// original name → tool-system name. Unique and valid
  /// ([Tool.isValidToolName]).
  static Map<String, String> toolNames(String slug, Iterable<String> tools) {
    final pre = prefix(slug);
    final room = maxToolName - pre.length;
    final out = <String, String>{};
    final used = <String>{};
    final originals = tools.toSet().toList()..sort();
    // Erst die unveränderten Namen, damit sie nie einem Hash-Namen weichen.
    for (final tool in originals) {
      if (_plain(tool) && tool.length <= room) {
        out[tool] = '$pre$tool';
        used.add('$pre$tool');
      }
    }
    for (final tool in originals) {
      if (out.containsKey(tool)) continue;
      final clean = tool.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      for (var length = hashLength; ; length += 2) {
        final hash = _hash(tool, length);
        final keep = room - hash.length - 1;
        final head = clean.length > keep ? clean.substring(0, keep) : clean;
        final name = '$pre${head}_$hash';
        if (used.add(name)) {
          out[tool] = name;
          break;
        }
      }
    }
    return out;
  }

  static bool _plain(String tool) =>
      tool.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(tool);

  static String _hash(String s, int length) {
    final hex = sha256.convert(utf8.encode(s)).toString();
    return hex.substring(0, length.clamp(1, hex.length));
  }
}
