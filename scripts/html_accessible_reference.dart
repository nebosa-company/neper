// Reference results for `e.fmt.html.accessible` (L040): Vaper's own accessibility tree builder
// (packages/vaper_engine_core/lib/src/a11y/accessibility_builder.dart) over the documents
// `html_accessible_vectors.mjs` writes. Usage:
//   dart run --packages=PACKAGE_CONFIG scripts/html_accessible_reference.dart INPUTS.json OUTPUT.json
// The snapshot the builder takes is derived from the DOM: the <body> subtree in document order, one node for each element
// (a block) and for each text node (a text node with one run, carrying the href of the nearest enclosing <a href>).
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:vaper_protocol/vaper_protocol.dart';

import 'file:///D:/repos/vaper/packages/vaper_engine_core/lib/src/a11y/accessibility_builder.dart';

String? hrefAbove(dom.Node n) {
  for (dom.Element? p = n.parent; p != null; p = p.parent) {
    if (p.localName == 'a' && p.attributes.containsKey('href')) return p.attributes['href'];
  }
  return null;
}

void walk(dom.Node n, int parent, List<SnapshotNode> nodes, Map<int, dom.Element> els) {
  for (final c in n.nodes) {
    if (c is dom.Element) {
      final id = nodes.length;
      nodes.add(SnapshotNode(id: id, parentIndex: parent, kind: SnapshotNodeKind.block, style: const SnapshotStyle()));
      els[id] = c;
      walk(c, id, nodes, els);
    } else if (c is dom.Text) {
      final id = nodes.length;
      nodes.add(SnapshotNode(
          id: id,
          parentIndex: parent,
          kind: SnapshotNodeKind.text,
          style: const SnapshotStyle(),
          runs: [InlineRun(text: c.data, linkHref: hrefAbove(c))]));
    }
  }
}

Map<String, Object?> encode(AccessibilityNode n) {
  final o = <String, Object?>{'r': n.role.name, 'i': n.nodeId};
  if (n.name.isNotEmpty) o['n'] = n.name;
  if (n.value != null) o['v'] = n.value;
  if (n.headingLevel != null) o['l'] = n.headingLevel;
  if (n.checked != null) o['c'] = n.checked;
  if (n.checkedMixed) o['cm'] = true;
  if (n.disabled) o['d'] = true;
  if (n.expanded != null) o['x'] = n.expanded;
  if (n.selected != null) o['s'] = n.selected;
  if (n.isRequired) o['q'] = true;
  if (n.invalid) o['iv'] = true;
  if (n.valueNow != null) o['vn'] = n.valueNow;
  if (n.valueMin != null) o['vmin'] = n.valueMin;
  if (n.valueMax != null) o['vmax'] = n.valueMax;
  if (n.linkUrl != null) o['u'] = n.linkUrl;
  if (n.focusable) o['f'] = true;
  o['k'] = [for (final c in n.children) encode(c)];
  return o;
}

void main(List<String> args) {
  final inputs = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
  final out = <Object?>[];
  for (final input in inputs) {
    final doc = parse(input as String);
    final body = doc.body!;
    final nodes = <SnapshotNode>[];
    final els = <int, dom.Element>{};
    nodes.add(SnapshotNode(id: 0, parentIndex: -1, kind: SnapshotNodeKind.block, style: const SnapshotStyle()));
    els[0] = body;
    walk(body, 0, nodes, els);
    final tree = buildAccessibilityTree(nodes: nodes, nodeElements: els, document: doc);
    out.add(tree == null ? null : encode(tree));
  }
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
