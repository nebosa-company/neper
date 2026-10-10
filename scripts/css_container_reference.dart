// Reference results for `e.fmt.css.container` (L040): Vaper's own container-query conditions
// (packages/vaper_engine_core/lib/src/css/container_query.dart) over the trees `css_container_vectors.mjs` writes.
// Usage: dart run scripts/css_container_reference.dart INPUTS.json OUTPUT.json.
import 'dart:convert';
import 'dart:io';

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/container_query.dart';

ContainerCondition build(Map<String, dynamic> j) {
  switch (j['t']) {
    case 'and':
      return ContainerAnd([for (final p in j['p'] as List<dynamic>) build(p as Map<String, dynamic>)]);
    case 'or':
      return ContainerOr([for (final p in j['p'] as List<dynamic>) build(p as Map<String, dynamic>)]);
    case 'not':
      return ContainerNot(build(j['p'] as Map<String, dynamic>));
    case 'unknown':
      return const ContainerUnknown();
    default:
      final kind = ContainerFeatureKind.values.firstWhere((k) => k.name == j['f']);
      final op = ContainerOp.values.firstWhere((o) => o.name == j['o']);
      return ContainerFeature(kind, op, (j['v'] as num).toDouble());
  }
}

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final input in inputs) {
    final m = input as Map<String, dynamic>;
    final c = build(m['c'] as Map<String, dynamic>);
    final results = <Object?>[];
    for (final s in m['sizes'] as List<dynamic>) {
      final sm = s as Map<String, dynamic>;
      final w = (sm['w'] as num?)?.toDouble();
      final h = (sm['h'] as num?)?.toDouble();
      results.add(c.evaluate(w, h));
    }
    out.add({'e': results, 'block': c.usesBlockAxis});
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
