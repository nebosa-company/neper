// Reference results for `e.ui.interpolate` (L039): Vaper's own interpolation kernels
// (packages/vaper_css_values/lib/src/interpolate.dart) over the operations `ui_interpolate_vectors.mjs` writes.
// Usage: dart run scripts/ui_interpolate_reference.dart INPUTS.json OUTPUT.json.
import 'dart:convert';
import 'dart:io';

import 'file:///D:/repos/vaper/packages/vaper_css_values/lib/src/interpolate.dart';

List<double> d(dynamic l) => [for (final x in l as List<dynamic>) (x as num).toDouble()];

void main(List<String> args) {
  final ops = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final o in ops) {
    final m = o as Map<String, dynamic>;
    switch (m['op']) {
      case 'lerp':
        out.add([lerpDouble((m['a'] as num).toDouble(), (m['b'] as num).toDouble(), (m['t'] as num).toDouble())]);
      case 'color':
        out.add([lerpColorArgb(m['a'] as int, m['b'] as int, (m['t'] as num).toDouble())]);
      case 'bezier':
        out.add([cubicBezier((m['x1'] as num).toDouble(), (m['y1'] as num).toDouble(), (m['x2'] as num).toDouble(), (m['y2'] as num).toDouble(), (m['t'] as num).toDouble())]);
      case 'affine':
        out.add(lerpAffine(d(m['a']), d(m['b']), (m['t'] as num).toDouble()));
      case 'decompose':
        final r = decompose2d(d(m['m']));
        out.add([r.translateX, r.translateY, r.scaleX, r.scaleY, r.angle, r.skew]);
      default:
        throw ArgumentError(m['op'] as String);
    }
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
