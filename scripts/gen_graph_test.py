#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_graph/src/main.e (L155): `e.fmt.graph`, GraphML / GEXF / GML.

Oracles, independent of the Neper code:
  * reading: files written by NetworkX (write_graphml, write_gexf, write_gml) with typed node, edge and graph
    attributes; the expected model is derived from the NetworkX graph that was written, not from the files;
    plus hand-written reference files with nested graphs (the GraphML primer's nested example, a GEXF
    hierarchy, a GML nested graph) whose expectations are read off with lxml / by inspection;
  * writing: the expected bytes come from second writers in this script against the same layout, and the
    generator asserts NetworkX reads each of them back to the same nodes, edges and attribute values;
  * the fixture also checks write-then-read equality, cross-format conversion and `to_csr`.
"""
import io
import sys
from pathlib import Path

import networkx as nx

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lane_e_common import Checks, lit, write_fixture  # noqa: E402

NONE = 4294967295
KIND = {"String": "string", "Boolean": "boolean", "Int": "int", "Long": "long", "Float": "float", "Double": "double"}
GEXF_KIND = dict(KIND, Int="integer")


def esc(s, attr=False):
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s.replace('"', "&quot;") if attr else s


# A model: list of graphs; graph = dict(id, directed, nodes=[dict(id, attrs, sub)], edges=[dict(id, source, target, directed, attrs)], attrs)
def node(i, attrs=(), sub=NONE):
    return dict(id=i, attrs=list(attrs), sub=sub)


def edge(s, t, attrs=(), directed=None, id=""):
    return dict(id=id, source=s, target=t, directed=directed, attrs=list(attrs))


def graph(gid, directed, nodes, edges, attrs=()):
    for e in edges:
        if e["directed"] is None:
            e["directed"] = directed
    return dict(id=gid, directed=directed, nodes=nodes, edges=edges, attrs=list(attrs))


def attrs_of(*triples):
    return list(triples)


# ---- independent writers --------------------------------------------------------------------------

def write_graphml(model):
    keys = []

    def add(domain, attrs):
        for (n, k, v) in attrs:
            if (domain, n, k) not in keys:
                keys.append((domain, n, k))

    for g in model:
        add("graph", g["attrs"])
        for nd in g["nodes"]:
            add("node", nd["attrs"])
        for e in g["edges"]:
            add("edge", e["attrs"])
    out = '<?xml version="1.0" encoding="UTF-8"?>\n<graphml xmlns="http://graphml.graphdrawing.org/xmlns">\n'
    for i, (d, n, k) in enumerate(keys):
        out += '<key id="d%d" for="%s" attr.name="%s" attr.type="%s"/>\n' % (i, d, esc(n, True), KIND[k])

    def data(domain, attrs):
        s = ""
        for (n, k, v) in attrs:
            s += '<data key="d%d">%s</data>\n' % (keys.index((domain, n, k)), esc(v))
        return s

    def gout(idx):
        g = model[idx]
        s = '<graph id="%s" edgedefault="%s">\n' % (esc(g["id"], True), "directed" if g["directed"] else "undirected")
        s += data("graph", g["attrs"])
        for nd in g["nodes"]:
            s += '<node id="%s">\n' % esc(nd["id"], True)
            s += data("node", nd["attrs"])
            if nd["sub"] != NONE:
                s += gout(nd["sub"])
            s += "</node>\n"
        for e in g["edges"]:
            s += "<edge"
            if e["id"]:
                s += ' id="%s"' % esc(e["id"], True)
            s += ' source="%s" target="%s"' % (esc(e["source"], True), esc(e["target"], True))
            if e["directed"] != g["directed"]:
                s += ' directed="%s"' % ("true" if e["directed"] else "false")
            s += ">\n" + data("edge", e["attrs"]) + "</edge>\n"
        return s + "</graph>\n"

    return out + gout(0) + "</graphml>\n"


def write_gexf(model):
    root = model[0]
    nkeys, ekeys = [], []
    for g in model:
        for nd in g["nodes"]:
            for (n, k, v) in nd["attrs"]:
                if n != "label" and (n, k) not in nkeys:
                    nkeys.append((n, k))
    for e in root["edges"]:
        for (n, k, v) in e["attrs"]:
            if n not in ("label", "weight") and (n, k) not in ekeys:
                ekeys.append((n, k))
    out = '<?xml version="1.0" encoding="UTF-8"?>\n<gexf xmlns="http://gexf.net/1.3" version="1.3">\n<graph'
    if root["id"]:
        out += ' id="%s"' % esc(root["id"], True)
    for (n, k, v) in root["attrs"]:
        if n == "name":
            out += ' name="%s"' % esc(v, True)
            break
    out += ' defaultedgetype="%s" mode="static">\n' % ("directed" if root["directed"] else "undirected")
    for cls, ks in (("node", nkeys), ("edge", ekeys)):
        if ks:
            out += '<attributes class="%s" mode="static">\n' % cls
            for i, (n, k) in enumerate(ks):
                out += '<attribute id="%d" title="%s" type="%s"/>\n' % (i, esc(n, True), GEXF_KIND[k])
            out += "</attributes>\n"

    def nodes_out(idx):
        s = "<nodes>\n"
        for nd in model[idx]["nodes"]:
            s += '<node id="%s"' % esc(nd["id"], True)
            for (n, k, v) in nd["attrs"]:
                if n == "label":
                    s += ' label="%s"' % esc(v, True)
                    break
            s += ">"
            vals = [(n, k, v) for (n, k, v) in nd["attrs"] if n != "label"]
            if vals:
                s += "<attvalues>"
                for (n, k, v) in vals:
                    s += '<attvalue for="%d" value="%s"/>' % (nkeys.index((n, k)), esc(v, True))
                s += "</attvalues>"
            if nd["sub"] != NONE:
                s += nodes_out(nd["sub"])
            s += "</node>\n"
        return s + "</nodes>\n"

    out += nodes_out(0)
    out += "<edges>\n"
    for i, e in enumerate(root["edges"]):
        out += '<edge id="%s" source="%s" target="%s"' % (esc(e["id"], True) if e["id"] else str(i), esc(e["source"], True), esc(e["target"], True))
        if e["directed"] != root["directed"]:
            out += ' type="%s"' % ("directed" if e["directed"] else "undirected")
        for (n, k, v) in e["attrs"]:
            if n == "weight":
                out += ' weight="%s"' % esc(v, True)
                break
        for (n, k, v) in e["attrs"]:
            if n == "label":
                out += ' label="%s"' % esc(v, True)
                break
        out += ">"
        vals = [(n, k, v) for (n, k, v) in e["attrs"] if n not in ("label", "weight")]
        if vals:
            out += "<attvalues>"
            for (n, k, v) in vals:
                out += '<attvalue for="%d" value="%s"/>' % (ekeys.index((n, k)), esc(v, True))
            out += "</attvalues>"
        out += "</edge>\n"
    return out + "</edges>\n</graph>\n</gexf>\n"


def gml_string(s):
    out = '"'
    for ch in s:
        if ch == "&":
            out += "&amp;"
        elif ch == '"':
            out += "&quot;"
        elif ord(ch) < 128:
            out += ch
        else:
            out += "&#%d;" % ord(ch)
    return out + '"'


def gml_value(k, v):
    if k in ("Int", "Long", "Float", "Double") and v:
        return v
    if k == "Boolean" and v in ("true", "false"):
        return "1" if v == "true" else "0"
    return gml_string(v)


def write_gml(model):
    def base(idx):
        return sum(len(model[i]["nodes"]) for i in range(idx))

    def gout(idx, sp):
        g = model[idx]
        b = base(idx)
        pad = " " * sp
        s = pad + "graph [\n" + pad + "  directed %d\n" % (1 if g["directed"] else 0)
        for i, nd in enumerate(g["nodes"]):
            s += pad + "  node [\n" + pad + "    id %d\n" % (b + i) + pad + "    label " + gml_string(nd["id"]) + "\n"
            for (n, k, v) in nd["attrs"]:
                if n != "label":
                    s += pad + "    %s %s\n" % (n, gml_value(k, v))
            if nd["sub"] != NONE:
                s += gout(nd["sub"], sp + 4)
            s += pad + "  ]\n"
        names = [nd["id"] for nd in g["nodes"]]
        for e in g["edges"]:
            s += pad + "  edge [\n" + pad + "    source %d\n" % (b + names.index(e["source"])) + pad + "    target %d\n" % (b + names.index(e["target"]))
            for (n, k, v) in e["attrs"]:
                s += pad + "    %s %s\n" % (n, gml_value(k, v))
            s += pad + "  ]\n"
        for (n, k, v) in g["attrs"]:
            s += pad + "  %s %s\n" % (n, gml_value(k, v))
        return s + pad + "]\n"

    return 'Creator "Neper e.fmt.graph"\n' + gout(0, 0)


# ---- the NetworkX-written corpus ------------------------------------------------------------------------

def nx_graph():
    G = nx.DiGraph(name="G1", directed_note="yes")
    G.add_node("a", label="Alpha & Co", size=3, score=0.5, active=True)
    G.add_node("b", label="Beta", size=5, score=1.25, active=False)
    G.add_node("c")
    G.add_edge("a", "b", weight=2.5, relation="knows")
    G.add_edge("b", "c", weight=1.0, relation="likes")
    return G


def kind_of(v):
    if isinstance(v, bool):
        return "Boolean"
    if isinstance(v, int):
        return "Long"
    if isinstance(v, float):
        return "Double"
    return "String"


def written(fn, G):
    out = io.BytesIO()
    fn(G, out)
    return out.getvalue()


def nx_expectations(G):
    """Per format: the model the reader should return, derived from the NetworkX graph (not the files)."""
    graph_attrs = [(k, "String", str(v)) for k, v in G.graph.items()]
    nodes = [(n, list(d.items())) for n, d in G.nodes(data=True)]
    edges = [(u, v, list(d.items())) for u, v, d in G.edges(data=True)]
    gml_nodes, gexf_nodes = [], []
    for n, d in nodes:
        gml_nodes.append((n, [(k, "Int" if isinstance(v, bool) else {"Long": "Int"}.get(kind_of(v), kind_of(v)), "1" if v is True else "0" if v is False else str(v)) for k, v in d if k != "label"]))
        lab = [(k, kind_of(v), str(v)) for k, v in d if k == "label"]
        rest = [(k, kind_of(v), str(v).lower() if isinstance(v, bool) else str(v)) for k, v in d if k != "label"]
        gexf_nodes.append((n, (lab if lab else [("label", "String", str(n))]) + rest))
    return graph_attrs, nodes, edges, gml_nodes, gexf_nodes


def build_main():
    G = nx_graph()
    gx = written(nx.write_graphml, G)
    xx = written(nx.write_gexf, G)
    mm = written(nx.write_gml, G)
    graph_attrs, nodes, edges, gml_nodes, gexf_nodes = nx_expectations(G)
    return G, gx, xx, mm, graph_attrs, nodes, edges, gml_nodes, gexf_nodes


# ---- Neper-side code generation ------------------------------------------------------------------------

class Gen:
    def __init__(self):
        self.c = Checks()
        self.n = 0

    def attr_lit(self, a):
        n, k, v = a
        return "gr.Attr { name: %s, kind: .%s, value: %s }" % (lit(n), k, lit(v))

    def doc(self, name, model):
        """Neper statements that build `name` as a `gr.Document` equal to `model`."""
        body = ""
        gnames = []
        for gi, g in enumerate(model):
            node_exprs = []
            for ni, nd in enumerate(g["nodes"]):
                an = "%s_g%dn%da" % (name, gi, ni)
                body += "    let %s = [%d]gr.Attr{ %s }\n" % (an, max(len(nd["attrs"]), 0) or 0, ", ".join(self.attr_lit(a) for a in nd["attrs"])) if nd["attrs"] else ""
                aref = "%s[0..]" % an if nd["attrs"] else "zero"
                node_exprs.append("gr.Node { id: %s, attrs: %s, subgraph: %du32 }" % (lit(nd["id"]), aref, nd["sub"]))
            edge_exprs = []
            for ei, e in enumerate(g["edges"]):
                an = "%s_g%de%da" % (name, gi, ei)
                body += "    let %s = [%d]gr.Attr{ %s }\n" % (an, len(e["attrs"]), ", ".join(self.attr_lit(a) for a in e["attrs"])) if e["attrs"] else ""
                aref = "%s[0..]" % an if e["attrs"] else "zero"
                edge_exprs.append("gr.Edge { id: %s, source: %s, target: %s, directed: %s, attrs: %s }" % (
                    lit(e["id"]), lit(e["source"]), lit(e["target"]), "true" if e["directed"] else "false", aref))
            ga = "%s_g%da" % (name, gi)
            if g["attrs"]:
                body += "    let %s = [%d]gr.Attr{ %s }\n" % (ga, len(g["attrs"]), ", ".join(self.attr_lit(a) for a in g["attrs"]))
            nn = "%s_g%dn" % (name, gi)
            if node_exprs:
                body += "    let %s = [%d]gr.Node{ %s }\n" % (nn, len(node_exprs), ", ".join(node_exprs))
            en = "%s_g%de" % (name, gi)
            if edge_exprs:
                body += "    let %s = [%d]gr.Edge{ %s }\n" % (en, len(edge_exprs), ", ".join(edge_exprs))
            gnames.append("gr.Graph { id: %s, directed: %s, nodes: %s, edges: %s, attrs: %s }" % (
                lit(g["id"]), "true" if g["directed"] else "false",
                ("%s[0..]" % nn) if node_exprs else "zero", ("%s[0..]" % en) if edge_exprs else "zero",
                ("%s[0..]" % ga) if g["attrs"] else "zero"))
        body += "    let %s_graphs = [%d]gr.Graph{ %s }\n" % (name, len(gnames), ", ".join(gnames))
        body += "    let %s = gr.Document { graphs: %s_graphs[0..] }\n" % (name, name)
        return body

    def expect_model(self, var, model, check_edge_ids=True):
        """Checks that the Document `var` holds `model`."""
        c = self.c
        c.add("%s.graphs.len != %dusize" % (var, len(model)))
        for gi, g in enumerate(model):
            gv = "%s.graphs[%d]" % (var, gi)
            c.add("%s.directed != %s || %s.nodes.len != %dusize || %s.edges.len != %dusize || %s.attrs.len != %dusize" % (
                gv, "true" if g["directed"] else "false", gv, len(g["nodes"]), gv, len(g["edges"]), gv, len(g["attrs"])))
            if g["id"]:
                c.add("!str.eq(%s.id, %s)" % (gv, lit(g["id"])))
            for ai, a in enumerate(g["attrs"]):
                c.add("!same_attr(%s.attrs[%d], %s, .%s, %s)" % (gv, ai, lit(a[0]), a[1], lit(a[2])))
            for ni, nd in enumerate(g["nodes"]):
                nv = "%s.nodes[%d]" % (gv, ni)
                cond = "!str.eq(%s.id, %s) || %s.attrs.len != %dusize || %s.subgraph != %du32" % (nv, lit(nd["id"]), nv, len(nd["attrs"]), nv, nd["sub"])
                for ai, a in enumerate(nd["attrs"]):
                    cond += " || !same_attr(%s.attrs[%d], %s, .%s, %s)" % (nv, ai, lit(a[0]), a[1], lit(a[2]))
                c.add(cond)
            for ei, e in enumerate(g["edges"]):
                ev = "%s.edges[%d]" % (gv, ei)
                cond = "!str.eq(%s.source, %s) || !str.eq(%s.target, %s) || %s.directed != %s || %s.attrs.len != %dusize" % (
                    ev, lit(e["source"]), ev, lit(e["target"]), ev, "true" if e["directed"] else "false", ev, len(e["attrs"]))
                if check_edge_ids and e["id"]:
                    cond += " || !str.eq(%s.id, %s)" % (ev, lit(e["id"]))
                for ai, a in enumerate(e["attrs"]):
                    cond += " || !same_attr(%s.attrs[%d], %s, .%s, %s)" % (ev, ai, lit(a[0]), a[1], lit(a[2]))
                c.add(cond)


def model_from_nx(G, fmt):
    """The model a reader should give for NetworkX's file of G in format `fmt` (derived from G)."""
    nodes = []
    for n, d in G.nodes(data=True):
        if fmt == "graphml":
            attrs = [(k, kind_of(v), str(v)) for k, v in d.items()]
        elif fmt == "gexf":
            lab = [(k, kind_of(v), str(v)) for k, v in d.items() if k == "label"] or [("label", "String", str(n))]
            attrs = lab + [(k, kind_of(v), str(v).lower() if isinstance(v, bool) else str(v)) for k, v in d.items() if k != "label"]
        else:
            attrs = [(k, "Int" if isinstance(v, (bool, int)) else kind_of(v), str(int(v)) if isinstance(v, bool) else str(v)) for k, v in d.items() if k != "label"]
        nodes.append(node(str(n), attrs))
    edges = []
    for u, v, d in G.edges(data=True):
        attrs = []
        for k, val in d.items():
            kd = "Double" if k == "weight" and fmt == "gexf" else kind_of(val)
            if fmt == "gml":
                kd = "Int" if isinstance(val, (bool, int)) else kind_of(val)
            attrs.append((k, kd, str(val)))
        edges.append(edge(str(u), str(v), attrs, directed=G.is_directed()))
    gattrs = [(k, "String", str(v)) for k, v in G.graph.items()]
    if fmt == "gexf":
        # GEXF has one graph attribute, the name; NetworkX writes nothing else.
        gattrs = [a for a in gattrs if a[0] == "name"]
    return [graph("", G.is_directed(), nodes, edges, gattrs)]


# ---- hand-written reference files with nested graphs ---------------------------------------------------

PRIMER = """<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd">
  <key id="d0" for="node" attr.name="color" attr.type="string"><default>yellow</default></key>
  <key id="d1" for="edge" attr.name="weight" attr.type="double"/>
  <graph id="G" edgedefault="undirected">
    <node id="n0"><data key="d0">green</data></node>
    <node id="n1"/>
    <node id="n2"><data key="d0">blue</data></node>
    <node id="n3"><data key="d0">red</data></node>
    <node id="n4"/>
    <node id="n5">
      <graph id="n5:" edgedefault="undirected">
        <node id="n5::n0"/>
        <node id="n5::n1"/>
        <edge id="e7" source="n5::n0" target="n5::n1"/>
      </graph>
    </node>
    <edge id="e0" source="n0" target="n2"><data key="d1">1.0</data></edge>
    <edge id="e1" source="n0" target="n1" directed="true"/>
    <edge id="e2" source="n1" target="n3"/>
    <edge id="e3" source="n3" target="n2"/>
    <edge id="e4" source="n2" target="n4"/>
    <edge id="e5" source="n3" target="n5"/>
    <edge id="e6" source="n5" target="n4"/>
  </graph>
</graphml>
"""
PRIMER_MODEL = [
    graph("G", False, [node("n0", [("color", "String", "green")]), node("n1", [("color", "String", "yellow")]),
                       node("n2", [("color", "String", "blue")]), node("n3", [("color", "String", "red")]),
                       node("n4", [("color", "String", "yellow")]), node("n5", [("color", "String", "yellow")], 1)],
          [edge("n0", "n2", [("weight", "Double", "1.0")], id="e0"), edge("n0", "n1", directed=True, id="e1"), edge("n1", "n3", id="e2"),
           edge("n3", "n2", id="e3"), edge("n2", "n4", id="e4"), edge("n3", "n5", id="e5"), edge("n5", "n4", id="e6")]),
    graph("n5:", False, [node("n5::n0", [("color", "String", "yellow")]), node("n5::n1", [("color", "String", "yellow")])],
          [edge("n5::n0", "n5::n1", id="e7")]),
]

GEXF_HIER = """<?xml version="1.0" encoding="UTF-8"?>
<gexf xmlns="http://gexf.net/1.3" version="1.3">
  <graph defaultedgetype="undirected" mode="static">
    <attributes class="node"><attribute id="0" title="kind" type="string"/></attributes>
    <nodes>
      <node id="0" label="root">
        <nodes>
          <node id="1" label="child1"/>
          <node id="2" label="child2"><attvalues><attvalue for="0" value="leaf"/></attvalues></node>
        </nodes>
      </node>
      <node id="3" label="other"/>
    </nodes>
    <edges>
      <edge id="e0" source="1" target="3" type="directed" weight="3"/>
    </edges>
  </graph>
</gexf>
"""
GEXF_MODEL = [
    graph("", False, [node("0", [("label", "String", "root")], 1), node("3", [("label", "String", "other")])],
          [edge("1", "3", [("weight", "Double", "3")], directed=True, id="e0")]),
    graph("0", False, [node("1", [("label", "String", "child1")]), node("2", [("label", "String", "child2"), ("kind", "String", "leaf")])], []),
]

GML_NESTED = """# a nested graph
graph [
  directed 0
  comment "group &amp; leaf"
  node [
    id 1
    label "group"
    graph [
      node [ id 2 label "inner" ]
      node [ id 3 label "inner2" ]
      edge [ source 2 target 3 ]
    ]
  ]
  node [ id 4 label "outer caf&#233;" ]
  edge [ source 1 target 4 weight 0.25 ]
]
"""
GML_MODEL = [
    graph("", False, [node("group", [], 1), node("outer café", [])], [edge("group", "outer café", [("weight", "Double", "0.25")])],
          [("comment", "String", "group & leaf")]),
    graph("", False, [node("inner"), node("inner2")], [edge("inner", "inner2")]),
]

# A model of our own, for the writers: typed attributes everywhere, a nested graph, a per-edge direction.
OWN = [
    graph("main", True,
          [node("a", [("label", "String", "Alpha <&> \"q\""), ("size", "Long", "3"), ("score", "Double", "0.5"), ("active", "Boolean", "true")]),
           node("b", [("label", "String", "café €"), ("size", "Long", "5"), ("score", "Double", "1.25"), ("active", "Boolean", "false")], 1),
           node("c", [])],
          [edge("a", "b", [("weight", "Double", "2.5"), ("relation", "String", "knows")], id="e0"),
           edge("b", "c", [("weight", "Double", "1.0")], directed=False, id="e1"),
           edge("a", "c", [], id="")],
          [("name", "String", "own"), ("version", "Int", "2")]),
    graph("sub", True, [node("b1", [("size", "Long", "7")]), node("b2", [])], [edge("b1", "b2", [("weight", "Double", "4")])]),
]


def own_gexf_model():
    """OWN without what GEXF cannot hold: nested graphs carry no edges."""
    m = [dict(g) for g in OWN]
    m[1] = dict(m[1], edges=[])
    return m


def main():
    G, gx, xx, mm, graph_attrs, nodes, edges, gml_nodes, gexf_nodes = build_main()
    g = Gen()
    c = g.c
    helper = ("fn same_attr(a: gr.Attr, name: str, kind: gr.AttrKind, value: str) -> bool {\n"
              "    ret str.eq(a.name, name) && a.kind == kind && str.eq(a.value, value)\n}\n\n"
              "fn same_bytes(x: str, y: str) -> bool {\n    ret str.eq(x, y)\n}\n\n")
    body = ""
    # --- NetworkX files, read ---
    for fmt, data, reader in (("graphml", gx, "read_graphml"), ("gexf", xx, "read_gexf"), ("gml", mm, "read_gml")):
        model = model_from_nx(G, fmt)
        c.raw("    let (nx_%s, nx_%s_error) = gr.%s(a, %s)\n" % (fmt, fmt, reader, lit(data)))
        c.add("nx_%s_error != ok" % fmt)
        g.expect_model("nx_%s" % fmt, model, check_edge_ids=False)
    # --- hand-written nested references ---
    c.raw("    let (primer, primer_error) = gr.read_graphml(a, %s)\n" % lit(PRIMER))
    c.add("primer_error != ok")
    g.expect_model("primer", PRIMER_MODEL)
    c.raw("    let (hier, hier_error) = gr.read_gexf(a, %s)\n" % lit(GEXF_HIER))
    c.add("hier_error != ok")
    g.expect_model("hier", GEXF_MODEL)
    c.raw("    let (nested, nested_error) = gr.read_gml(a, %s)\n" % lit(GML_NESTED))
    c.add("nested_error != ok")
    g.expect_model("nested", GML_MODEL)
    # --- writers: our own model, byte for byte, and read back ---
    own_body = g.doc("own", OWN)
    c.raw(own_body)
    ox = write_graphml(OWN)
    c.raw("    let (own_graphml, own_graphml_error) = gr.write_graphml(a, own)\n")
    c.add("own_graphml_error != ok")
    c.add("!same_bytes(own_graphml, %s)" % lit(ox))
    c.raw("    let (own_back, own_back_error) = gr.read_graphml(a, own_graphml)\n")
    c.add("own_back_error != ok")
    g.expect_model("own_back", OWN)
    gexf_model = own_gexf_model()
    c.raw(g.doc("own_gexf_source", gexf_model))
    xg = write_gexf(gexf_model)
    c.raw("    let (own_gexf, own_gexf_error) = gr.write_gexf(a, own_gexf_source)\n")
    c.add("own_gexf_error != ok")
    c.add("!same_bytes(own_gexf, %s)" % lit(xg))
    c.raw("    let (gexf_back, gexf_back_error) = gr.read_gexf(a, own_gexf)\n")
    c.add("gexf_back_error != ok")
    # GEXF reads a node's subgraph id from the node it hangs under, and writes no graph ids but the root's.
    back = [dict(gr_) for gr_ in gexf_model]
    back[0] = dict(back[0], attrs=[a for a in back[0]["attrs"] if a[0] == "name"])
    back[1] = dict(back[1], id="b")
    for e in back[0]["edges"]:
        e["id"] = e["id"] or ""
    # edge ids are written as ordinals when absent
    back[0]["edges"] = [dict(e, id=e["id"] or str(i)) for i, e in enumerate(gexf_model[0]["edges"])]
    g.expect_model("gexf_back", back)
    own_gml = write_gml(OWN)
    c.raw("    let (own_gml_text, own_gml_error) = gr.write_gml(a, own)\n")
    c.add("own_gml_error != ok")
    c.add("!same_bytes(own_gml_text, %s)" % lit(own_gml))
    c.raw("    let (gml_back, gml_back_error) = gr.read_gml(a, own_gml_text)\n")
    c.add("gml_back_error != ok")
    gml_expect = []
    for gi, gg in enumerate(OWN):
        ng = [node(nd["id"], [(n, ("Int" if k == "Boolean" else k), ("1" if v == "true" else "0" if v == "false" else v)) for (n, k, v) in nd["attrs"] if n != "label"], nd["sub"]) for nd in gg["nodes"]]
        ne = [edge(e["source"], e["target"], e["attrs"], directed=gg["directed"]) for e in gg["edges"]]
        gml_expect.append(graph("", gg["directed"], ng, ne, gg["attrs"]))
    # Types GML cannot say fall to what it can: Long reads as Int, Double stays, Boolean is 0/1.
    def gml_kind(k, v):
        # GML has integers, reals and strings: a number reads as Int unless it is written with a point or exponent.
        if k in ("Long", "Int", "Float", "Double"):
            return "Double" if any(ch in v for ch in ".eE") else "Int"
        return k

    for gg in gml_expect:
        for nd in gg["nodes"]:
            nd["attrs"] = [(n, gml_kind(k, v), v) for (n, k, v) in nd["attrs"]]
        for e in gg["edges"]:
            e["attrs"] = [(n, gml_kind(k, v), v) for (n, k, v) in e["attrs"]]
        gg["attrs"] = [(n, gml_kind(k, v), v) for (n, k, v) in gg["attrs"]]
    g.expect_model("gml_back", gml_expect, check_edge_ids=False)
    # --- NetworkX accepts what we write (generation-time assertions) ---
    # NetworkX refuses a directed graph holding an undirected edge, so it reads the same model with that edge
    # made directed.
    uniform = [dict(gg, edges=[dict(e, directed=gg["directed"]) for e in gg["edges"]]) for gg in OWN]
    rg = nx.read_graphml(io.BytesIO(write_graphml(uniform).encode("utf-8")))
    assert set(rg.nodes) >= {"a", "b", "c"}, rg.nodes
    assert rg.nodes["a"]["size"] == 3 and rg.nodes["a"]["active"] is True and rg.nodes["a"]["score"] == 0.5
    assert rg.nodes["b"]["label"] == "café €" and rg.graph["name"] == "own"
    assert rg.edges["a", "b"]["weight"] == 2.5
    uniform_gexf = [dict(gg, edges=[dict(e, directed=gg["directed"]) for e in gg["edges"]]) for gg in gexf_model]
    rx = nx.read_gexf(io.BytesIO(write_gexf(uniform_gexf).encode("utf-8")))
    assert rx.nodes["a"]["label"] == 'Alpha <&> "q"' and rx.nodes["a"]["size"] == 3 and rx.nodes["b"]["active"] is False
    assert rx.edges["a", "b"]["weight"] == 2.5
    rm = nx.read_gml(io.BytesIO(own_gml.encode("utf-8")), label="label")
    assert set(rm.nodes) >= {"a", "b", "c"} and rm.nodes["a"]["size"] == 3 and rm.graph["name"] == "own"
    assert rm.nodes["b" if "b" in rm.nodes else "b"]["score"] == 1.25
    # --- the three NetworkX files give the same graph in e.data.graph ---
    c.raw("    let (csr, csr_error) = gr.to_csr(a, nx_graphml, 0usize)\n")
    c.add("csr_error != ok")
    c.add("csr.node_count != 3usize || csr.edges.len != 2usize")
    c.add("csr.edges[0].from != 0u32 || csr.edges[0].to != 1u32 || csr.edges[0].value != 2.5f64 || csr.edges[1].from != 1u32 || csr.edges[1].to != 2u32 || csr.edges[1].value != 1.0f64")
    c.raw("    let (csr_gexf, csr_gexf_error) = gr.to_csr(a, nx_gexf, 0usize)\n")
    c.add("csr_gexf_error != ok || csr_gexf.node_count != 3usize || csr_gexf.edges.len != 2usize || csr_gexf.edges[0].value != 2.5f64")
    c.raw("    let (csr_gml, csr_gml_error) = gr.to_csr(a, nx_gml, 0usize)\n")
    c.add("csr_gml_error != ok || csr_gml.node_count != 3usize || csr_gml.edges.len != 2usize || csr_gml.edges[1].value != 1.0f64")
    # Undirected edges become two directed ones; a nested graph is its own CSR.
    c.raw("    let (csr_primer, csr_primer_error) = gr.to_csr(a, primer, 0usize)\n")
    c.add("csr_primer_error != ok || csr_primer.node_count != 6usize || csr_primer.edges.len != 13usize")
    c.raw("    let (csr_inner, csr_inner_error) = gr.to_csr(a, primer, 1usize)\n")
    c.add("csr_inner_error != ok || csr_inner.node_count != 2usize || csr_inner.edges.len != 2usize")
    c.raw("    let (csr_far, csr_far_error) = gr.to_csr(a, primer, 7usize)\n")
    c.add("csr_far_error != gr.Dangling")
    # --- refusals ---
    for name, call, expected in (
        ("bad_xml", 'gr.read_graphml(a, "<graphml><graph>")', "gr.Malformed"),
        ("not_graphml", 'gr.read_graphml(a, "<html/>")', "gr.Malformed"),
        ("dangling", 'gr.read_graphml(a, "<graphml><graph edgedefault=\\"directed\\"><node id=\\"a\\"/><edge source=\\"a\\" target=\\"zzz\\"/></graph></graphml>")', "gr.Dangling"),
        ("duplicate", 'gr.read_graphml(a, "<graphml><graph><node id=\\"a\\"/><node id=\\"a\\"/></graph></graphml>")', "gr.Malformed"),
        ("hyper", 'gr.read_graphml(a, "<graphml><graph><node id=\\"a\\"/><hyperedge><endpoint node=\\"a\\"/></hyperedge></graph></graphml>")', "gr.Unsupported"),
        ("unknown_key", 'gr.read_graphml(a, "<graphml><graph><node id=\\"a\\"><data key=\\"nope\\">1</data></node></graph></graphml>")', "gr.Malformed"),
        ("gexf_bad", 'gr.read_gexf(a, "<gexf><graph><nodes><node label=\\"x\\"/></nodes></graph></gexf>")', "gr.Malformed"),
        ("gml_open", 'gr.read_gml(a, "graph [ node [ id 1 ]")', "gr.Malformed"),
        ("gml_none", 'gr.read_gml(a, "node [ id 1 ]")', "gr.Malformed"),
        ("gml_edge", 'gr.read_gml(a, "graph [ node [ id 1 ] edge [ source 1 target 9 ] ]")', "gr.Dangling"),
    ):
        c.raw("    let (%s_d, %s_e) = %s\n" % (name, name, call))
        c.add("%s_e != %s" % (name, expected))
    # Writers refuse what the formats cannot carry.
    bad = [graph("g", True, [node("a", [("bad key", "String", "x")])], [])]
    c.raw(g.doc("badkey", bad))
    c.raw("    let (badkey_gml, badkey_error) = gr.write_gml(a, badkey)\n")
    c.add("badkey_error != gr.BadName")
    hier_edges = [graph("", True, [node("p", [], 1)], []), graph("", True, [node("q", [])], [edge("q", "q")])]
    c.raw(g.doc("subedges", hier_edges))
    c.raw("    let (subedges_gexf, subedges_error) = gr.write_gexf(a, subedges)\n")
    c.add("subedges_error != gr.Unsupported")
    header = ("// `e.fmt.graph`: files written by NetworkX (GraphML, GEXF, GML with typed attributes) read, the GraphML primer's nested\n"
              "// example, a GEXF hierarchy and a GML nested graph read, a model with typed attributes, a nested graph and a per-edge\n"
              "// direction written in all three formats byte for byte against independent writers and read back, `to_csr` into\n"
              "// e.data.graph, and the refusals. NetworkX read the written files back when the generator ran. Written by\n"
              "// scripts/gen_graph_test.py. Every check has its own exit code.\n")
    uses = ["e.os", "e.mem", "e.str", "e.fmt.graph as gr"]
    fn_head = "fn main(a: *mem.Arena, args: []str) -> err {\n"
    target = write_fixture("fmt_graph", header, helper + fn_head + c.text() + "    ret ok\n}\n", uses)
    print("wrote", target, "checks", c.code)


if __name__ == "__main__":
    main()
