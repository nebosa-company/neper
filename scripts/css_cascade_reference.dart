// Reference results for `e.fmt.css.cascade` (L040): Vaper's own StyleResolver cascade, its presentational hints and its
// rule index over the cases `css_cascade_vectors.mjs` writes. The mjs script copies Vaper's css library and renames the
// resolver's private `_cascade`, `_presentationalHints`, `_candidates` and `_RuleIndex` so this script can reach them
// (no other change); the package `vaper_css_copy` names that copy.
// Usage: dart run --packages=PACKAGE_CONFIG scripts/css_cascade_reference.dart INPUTS.json OUTPUT.json
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:vaper_css_copy/css/container_query.dart';
import 'package:vaper_css_copy/css/css_parser.dart';
import 'package:vaper_css_copy/css/css_tokenizer.dart';
import 'package:vaper_css_copy/css/selector.dart';
import 'package:vaper_css_copy/css/selector_parser.dart';
import 'package:vaper_css_copy/css/style_resolver.dart';

void collect(dom.Element e, List<dom.Element> out) {
  out.add(e);
  for (final c in e.children) {
    collect(c, out);
  }
}

Selector sel(String src) => parseSelectorListForRule(src, tokenizeCss(src)).first.selector;

ContainerCondition cond(Map<String, dynamic> j) {
  switch (j['t']) {
    case 'and':
      return ContainerAnd([for (final p in j['p'] as List<dynamic>) cond(p as Map<String, dynamic>)]);
    case 'or':
      return ContainerOr([for (final p in j['p'] as List<dynamic>) cond(p as Map<String, dynamic>)]);
    case 'not':
      return ContainerNot(cond(j['p'] as Map<String, dynamic>));
    case 'unknown':
      return const ContainerUnknown();
    default:
      final kind = ContainerFeatureKind.values.firstWhere((k) => k.name == j['f']);
      final op = ContainerOp.values.firstWhere((o) => o.name == j['o']);
      return ContainerFeature(kind, op, (j['v'] as num).toDouble());
  }
}

StyleRule rule(Map<String, dynamic> j) {
  return StyleRule(
    sel(j['sel'] as String),
    [
      for (final d in j['d'] as List<dynamic>)
        CssDeclaration((d as List<dynamic>)[0] as String, d[1] as String, important: d[2] as bool),
    ],
    j['src'] as int,
    layerPriority: j['layer'] as int?,
    containers: [
      for (final q in j['cont'] as List<dynamic>)
        ContainerQuery(cond((q as Map<String, dynamic>)['c'] as Map<String, dynamic>), name: q['n'] as String?),
    ],
    scopes: [
      for (final s in j['sc'] as List<dynamic>)
        ScopeRule(
          starts: [for (final x in (s as Map<String, dynamic>)['s'] as List<dynamic>) sel(x as String)],
          limits: [for (final x in s['l'] as List<dynamic>) sel(x as String)],
        ),
    ],
  );
}

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final input in inputs) {
    final m = input as Map<String, dynamic>;
    final doc = parse(m['html'] as String);
    final els = <dom.Element>[];
    collect(doc.documentElement!, els);
    final ua = [for (final r in m['ua'] as List<dynamic>) rule(r as Map<String, dynamic>)];
    final author = [for (final r in m['author'] as List<dynamic>) rule(r as Map<String, dynamic>)];
    final resolver = StyleResolver(uaRules: ua, authorRules: author);
    for (final c in m['stack'] as List<dynamic>) {
      final cm = c as Map<String, dynamic>;
      resolver.containerStack.add(ContainerSize(
        type: cm['k'] == 'size' ? ContainerAxisType.size : ContainerAxisType.inlineSize,
        names: [for (final n in cm['n'] as List<dynamic>) n as String],
        width: (cm['w'] as num?)?.toDouble(),
        height: (cm['h'] as num?)?.toDouble(),
      ));
    }
    final authorIndex = RuleIndex.build(author);
    final uaIndex = RuleIndex.build(ua);
    final per = <Object?>[];
    for (final e in els) {
      final w = resolver.cascadeForTest(e);
      final hints = resolver.presentationalHintsForTest(e);
      final ac = [for (final r in resolver.candidatesForTest(authorIndex, e)) author.indexOf(r)];
      final uc = [for (final r in resolver.candidatesForTest(uaIndex, e)) ua.indexOf(r)];
      per.add({
        't': e.localName,
        'p': e.parent == null ? -1 : els.indexOf(e.parent!),
        'w': w,
        'h': [for (final d in hints) [d.property, d.value]],
        'a': ac,
        'u': uc,
      });
    }
    out.add(per);
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
