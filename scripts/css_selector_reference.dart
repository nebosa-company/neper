// Reference results for `e.fmt.css.selector` (L038): Vaper's own selector parser and specificity
// (packages/vaper_engine_core/lib/src/css/selector_parser.dart, selector.dart) over the inputs
// `css_selector_vectors.mjs` writes. Usage: dart run scripts/css_selector_reference.dart INPUTS.json OUTPUT.json.
import 'dart:convert';
import 'dart:io';

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/css_tokenizer.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/selector.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/selector_parser.dart';

Map<String, Object?> simple(SimpleSelector s) {
  final o = <String, Object?>{'k': s.kind.name, 'n': s.name};
  if (s.argument.isNotEmpty) o['a'] = s.argument;
  if (s.attrCaseInsensitive) o['i'] = true;
  if (s.subSelectors.isNotEmpty) o['s'] = [for (final x in s.subSelectors) selector(x)];
  return o;
}

Map<String, Object?> selector(Selector s) => {
      'c': [
        for (final c in s.compounds) [for (final p in c.parts) simple(p)]
      ],
      'k': [for (final k in s.combinators) k.name],
      'sp': [s.specificity.ids, s.specificity.classes, s.specificity.types],
    };

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final src in inputs) {
    final s = src as String;
    final tokens = tokenizeCss(s);
    final list = parseSelectorListForRule(s, tokens);
    out.add([
      for (final r in list) {'sel': selector(r.selector), if (r.pseudo != null) 'p': r.pseudo!.name}
    ]);
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
