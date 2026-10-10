// Reference results for `e.fmt.woff` and `e.fmt.woff2` (L043): Vaper's own decoders over the inputs
// `woff_vectors.mjs` writes. Usage: dart run scripts/woff_reference.dart INPUTS.json OUTPUT.json
// (each input {k: 'woff'|'woff2', h: hex}; each output a hex string, null for a refusal, or "exc" for a throw).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/woff_decoder_io.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/net/woff2_decoder.dart';

Uint8List unhex(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hex(Uint8List b) {
  final s = StringBuffer();
  for (final v in b) {
    s.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return s.toString();
}

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final input in inputs) {
    final m = input as Map<String, dynamic>;
    final bytes = unhex(m['h'] as String);
    try {
      final r = m['k'] == 'woff' ? woffToSfnt(bytes) : woff2ToSfnt(bytes);
      out.add(r == null ? null : hex(r));
    } catch (_) {
      out.add('exc');
    }
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
