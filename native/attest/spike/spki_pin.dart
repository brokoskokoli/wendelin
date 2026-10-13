// WP43 Frage 8: SPKI-SHA256 des Serverzertifikats in reinem Dart.
// dart run spike/spki_pin.dart api.redpill.ai [erwartet_hex]
import 'dart:io';
import 'dart:convert';

/// Liest ein DER-TLV ab [p]; liefert (Tag, Wertstart, Wertende).
(int, int, int) tlv(List<int> d, int p) {
  final tag = d[p];
  var l = d[p + 1];
  var s = p + 2;
  if (l & 0x80 != 0) {
    final n = l & 0x7f;
    l = 0;
    for (var i = 0; i < n; i++) {
      l = (l << 8) | d[s + i];
    }
    s += n;
  }
  return (tag, s, s + l);
}

/// TBSCertificate: [0] version?, serial, sigAlg, issuer, validity, subject, SPKI.
List<int> spkiOf(List<int> der) {
  final cert = tlv(der, 0);
  final tbs = tlv(der, cert.$2);
  var p = tbs.$2;
  var e = tlv(der, p);
  if (e.$1 == 0xa0) p = e.$3; // explizite Version überspringen
  for (var i = 0; i < 5; i++) {
    p = tlv(der, p).$3; // serial, sigAlg, issuer, validity, subject
  }
  final spki = tlv(der, p);
  return der.sublist(p, spki.$3);
}

Future<void> main(List<String> a) async {
  final sw = Stopwatch()..start();
  final s = await SecureSocket.connect(a[0], 443,
      timeout: const Duration(seconds: 10));
  final spki = spkiOf(s.peerCertificate!.der);
  // SHA-256 im Spike per `openssl dgst`; in der App: package:crypto.
  print('${base64.encode(spki)} in ${sw.elapsedMilliseconds} ms');
  await s.close();
}
