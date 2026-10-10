// Reference results for `e.fmt.css.match` (L040): Vaper's own selector matcher
// (packages/vaper_engine_core/lib/src/css/selector_matcher.dart) over the documents and selector lists
// `css_match_vectors.mjs` writes. Usage:
//   dart run --packages=PACKAGE_CONFIG scripts/css_match_reference.dart INPUTS.json OUTPUT.json
// The packages file maps `html` and the Vaper packages (see scripts/css_match_vectors.mjs). Elements are numbered in
// document order from the root element.
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/css_tokenizer.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/selector.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/selector_matcher.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/selector_parser.dart';

void collect(dom.Element e, List<dom.Element> out) {
  out.add(e);
  for (final c in e.children) {
    collect(c, out);
  }
}

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final input in inputs) {
    final m = input as Map<String, dynamic>;
    final doc = parse(m['html'] as String);
    final els = <dom.Element>[];
    collect(doc.documentElement!, els);
    final st = m['state'] as Map<String, dynamic>?;
    int? id(String k) => st != null && st[k] != null ? els[(st[k] as int) % els.length].hashCode : null;
    Set<int>? within;
    if (st != null && st['focusWithin'] != null) {
      within = {for (final i in st['focusWithin'] as List<dynamic>) els[(i as int) % els.length].hashCode};
    }
    setPseudoClassState(PseudoClassState(hoverId: id('hover'), focusId: id('focus'), activeId: id('active'), focusWithinIds: within));
    final src = m['selector'] as String;
    final list = parseSelectorListForRule(src, tokenizeCss(src));
    final results = <String>[];
    for (final r in list) {
      final buf = StringBuffer();
      for (final e in els) {
        buf.write(selectorMatches(r.selector, e) ? '1' : '0');
      }
      results.add(buf.toString());
    }
    out.add({'tags': [for (final e in els) e.localName], 'r': results});
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
