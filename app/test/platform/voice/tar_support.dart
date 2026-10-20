import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show BZip2Encoder;

/// One tar header + body (GNU/ustar, checksum filled in).
List<int> tarEntry(
  String name,
  List<int> data, {
  String type = '0',
  String link = '',
  String prefix = '',
}) {
  final h = Uint8List(512);
  void put(int at, String s) => h.setRange(at, at + s.length, utf8.encode(s));
  put(0, name);
  put(100, '0000644');
  put(124, data.length.toRadixString(8).padLeft(11, '0'));
  put(136, '00000000000');
  put(148, '        ');
  put(156, type);
  put(157, link);
  put(257, 'ustar');
  put(263, '00');
  put(345, prefix);
  final sum = h.fold(0, (a, b) => a + b);
  put(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 ');
  final pad = (512 - data.length % 512) % 512;
  return [...h, ...data, ...List.filled(pad, 0)];
}

Uint8List tar(List<List<int>> entries) => Uint8List.fromList([
  for (final e in entries) ...e,
  ...List.filled(1024, 0),
]);

Uint8List bz2(List<int> bytes) =>
    Uint8List.fromList(BZip2Encoder().encodeBytes(bytes));
