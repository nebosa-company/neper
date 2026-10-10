// Reference results for `e.gfx.cssvalue` (L039): Vaper's own CSS value parsers
// (packages/vaper_css_values/lib/src/value.dart) over the operations `css_values_vectors.mjs` writes.
// Usage: dart run scripts/css_values_reference.dart INPUTS.json OUTPUT.json.
import 'dart:convert';
import 'dart:io';

import 'file:///D:/repos/vaper/packages/vaper_css_values/lib/src/value.dart';

double? d(dynamic x) => x == null ? null : (x as num).toDouble();

Object? length(Map<String, dynamic> m) {
  final b = m['bases'] as Map<String, dynamic>?;
  final l = parseLength(m['raw'] as String,
      emBase: d(b?['em']), remBase: d(b?['rem']), viewportWidth: d(b?['vw']), viewportHeight: d(b?['vh']));
  if (l == null) return null;
  final e = m['eval'] as Map<String, dynamic>?;
  final px = l.toPx(
      emBase: d(e?['em']),
      remBase: d(e?['rem']),
      percentBase: d(e?['percent']),
      viewportWidth: d(e?['vw']),
      viewportHeight: d(e?['vh']));
  return {'v': l.value, 'u': l.unit.name, 'o': l.pxOffset, 'p': px};
}

void main(List<String> args) {
  final ops = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final o in ops) {
    final m = o as Map<String, dynamic>;
    final raw = m['raw'] as String;
    switch (m['op']) {
      case 'length':
        out.add(length(m));
      case 'number':
        out.add(parseCssNumber(raw));
      case 'angle':
        out.add(parseCssAngleRadians(raw));
      case 'time':
        out.add(parseCssTimeSeconds(raw));
      case 'lightdark':
        out.add(pickLightDark(raw, dark: m['dark'] as bool));
      case 'color':
        out.add(parseColor(raw));
      case 'mix':
        out.add(parseColorMix(raw, currentColor: m['current'] as int?));
      case 'contrast':
        out.add(parseContrastColor(raw, currentColor: m['current'] as int?));
      case 'transform':
        out.add(parseTransform(raw));
      case 'translatePercent':
        final r = parseTranslatePercent(raw);
        out.add([r.$1, r.$2]);
      case 'origin':
        final r = parseTransformOrigin(raw);
        out.add([r.$1, r.$2]);
      default:
        throw ArgumentError(m['op'] as String);
    }
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
