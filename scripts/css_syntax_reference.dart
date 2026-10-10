// Reference results for `e.fmt.css.syntax` (L038): Vaper's own CSS Syntax 3 tokenizer and grammar
// (packages/vaper_engine_core/lib/src/css/css_tokenizer.dart, css_syntax.dart) over the inputs `css_syntax_vectors.mjs`
// writes. Usage: dart run scripts/css_syntax_reference.dart INPUTS.json OUTPUT.json. Offsets are mapped from UTF-16 code
// units to UTF-8 bytes, which is what the Neper tokenizer counts.
import 'dart:convert';
import 'dart:io';

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/css_tokenizer.dart';
import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/css/css_syntax.dart';

List<int> byteOffsets(String s) {
  final map = List<int>.filled(s.length + 1, 0);
  var bytes = 0;
  var i = 0;
  while (i < s.length) {
    map[i] = bytes;
    final u = s.codeUnitAt(i);
    if (u < 0x80) {
      bytes += 1;
      i += 1;
    } else if (u < 0x800) {
      bytes += 2;
      i += 1;
    } else if (u >= 0xD800 && u <= 0xDBFF && i + 1 < s.length) {
      map[i + 1] = bytes;
      bytes += 4;
      i += 2;
    } else {
      bytes += 3;
      i += 1;
    }
  }
  map[s.length] = bytes;
  return map;
}

Map<String, Object?> tok(CssToken t, List<int> m) {
  final o = <String, Object?>{'t': t.type.name, 's': m[t.start < 0 ? 0 : t.start], 'e': m[t.end < 0 ? 0 : t.end]};
  if (t.value.isNotEmpty) o['v'] = t.value;
  if (t.numericValue != null) o['nv'] = t.numericValue.toString();
  if (t.unit != null) o['u'] = t.unit;
  if (t.isInteger) o['i'] = true;
  if (t.hashIsId) o['h'] = true;
  return o;
}

List<Object?> toks(List<CssToken> l, List<int> m) => [for (final t in l) tok(t, m)];

Map<String, Object?> block(SimpleBlockNode b, List<int> m) => {'o': b.open.name, 'i': toks(b.inner, m)};

Map<String, Object?> rule(CssRuleNode r, List<int> m) {
  if (r is QualifiedRuleNode) return {'k': 'q', 'p': toks(r.prelude, m), 'b': block(r.block, m)};
  final a = r as AtRuleNode;
  return {'k': 'a', 'n': a.name, 'p': toks(a.prelude, m), if (a.block != null) 'b': block(a.block!, m)};
}

List<Object?> decls(List<Declaration> l, List<int> m) => [for (final d in l) {'n': d.name, 'v': toks(d.value, m), 'i': d.important}];

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final src in inputs) {
    final s = src as String;
    final m = byteOffsets(s);
    final tokens = tokenizeCss(s);
    final rules = parseCssRules(tokens);
    final ruleDecls = <Object?>[];
    for (final r in rules) {
      if (r is QualifiedRuleNode) {
        ruleDecls.add(decls(parseCssDeclarations([...r.block.inner, CssToken(CssTokenType.eof, s.length, s.length)]), m));
      }
    }
    out.add({
      'tokens': toks(tokens, m),
      'rules': [for (final r in rules) rule(r, m)],
      'decls': decls(parseCssDeclarations(tokens), m),
      'ruleDecls': ruleDecls,
    });
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
