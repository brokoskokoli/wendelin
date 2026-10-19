import 'dart:convert';
import 'dart:typed_data';

import 'package:wendelin_providers/wendelin_providers.dart';

import 'collateral_cache.dart';

/// [KdsCache] on top of the file [CollateralCache]: VCEK and AMD chain
/// survive a restart (the AMD KDS answers 429 when asked again). Entries
/// are only a cache, the Rust check verifies them on every attestation.
final class FileKdsCache implements KdsCache {
  /// Creates the cache; entries live [ttl].
  FileKdsCache(this._files, {this.ttl = const Duration(days: 7)});

  final CollateralCache _files;

  /// How long an entry is used.
  final Duration ttl;

  String _name(String key) => 'kds-$key';

  @override
  Future<KdsEntry?> load(String key) async {
    final c = _files.read(_name(key));
    if (c == null) return null;
    try {
      final m = jsonDecode(utf8.decode(c.json)) as Map<String, dynamic>;
      return KdsEntry(
        vcek: base64Decode(m['vcek'] as String),
        chain: m['chain'] as String,
        product: m['product'] as String,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(String key, KdsEntry entry) async {
    _files.write(
      _name(key),
      QuoteCollateral(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'vcek': base64Encode(entry.vcek),
              'chain': entry.chain,
              'product': entry.product,
            }),
          ),
        ),
        validUntil: _files.now().add(ttl),
      ),
    );
  }
}
