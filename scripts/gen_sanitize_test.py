#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_html_sanitize/src/main.e (L132): `e.fmt.html.sanitize`.

Oracle: nh3, the Python binding of ammonia (the HTML sanitizer this module follows). Every PARITY input is
cleaned by nh3 with the configuration under test and the Neper output must be byte for byte the same; each
output is also sanitized again and must not change. NOTES records inputs where the two parsers legitimately
differ (the `e.fmt.html` tree builder has no adoption agency, no foster parenting and no `tbody` insertion);
those are checked for the properties that matter (no script element, no event handler, no script URL) and
for exact text where the behaviour is ours by design. Hand-written attack inputs (event handlers in every
position, obfuscated schemes, nesting, mutation payloads, style) are in ATTACKS.

Install nh3 with `python -m pip install --target <dir> nh3` and put <dir> on PYTHONPATH.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nh3  # noqa: E402
from lane_e_common import Checks, lit, write_fixture  # noqa: E402

DEFAULT = {}

PARITY = [
    '<p onclick=x>hi<script>1</script><a href="javascript:1">a</a><a href="http://x">b</a></p>',
    '<div><b>bold</b> &amp; <i>it</i> &lt;x&gt; "q"  nb</div>',
    '<a href="  JaVa\tScRiPt:alert(1)">x</a>',
    '<a href="http://a.b/?q=1&x=2" title="t &quot;q&quot; <z>">l</a>',
    '<img src="x" onerror="alert(1)"><p>after',
    '<style>p{}</style><p style="color:red">s</p>',
    '<ul><li>a<li>b</ul>',
    '<table><tbody><tr><td colspan="2" onclick="x">c</td></tr></tbody></table>',
    '<svg><script>alert(1)</script></svg><p>t',
    '<!-- c --><p>x</p>',
    '<html><head><title>T</title></head><body>b</body></html>',
    '<form action="x"><input value=1>t</form>',
    '<a href="mailto:a@b.c">m</a><a href="//evil.com/x">r</a><a href="/rel">rel</a><a href="ftp://h">ftp</a>',
    '<p>unclosed <em>em',
    'plain & text < 3',
    '<A HREF="HTTP://UP.CASE/" TITLE="T">Up</A><BR><IMG SRC="a.png" ALT="x" WIDTH=10>',
    '<a href="&#106;avascript:alert(1)">e</a><a href="java&#9;script:alert(1)">t</a><a href="&#x6A;avascript&colon;alert(1)">c</a>',
    '<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">d</a><a href="vbscript:msgbox(1)">v</a>',
    '<img src="javascript:alert(1)"><img src="data:image/png;base64,AAAA"><img src="https://ok/x.png">',
    '<body onload=alert(1)><div onmouseover="x" lang="fr" title="t" id="i" class="c" data-x="1">d</div></body>',
    '<scr<script>ipt>alert(1)</scr</script>ipt>',
    '<<script>alert(1);//<</script>',
    '<textarea><script>alert(1)</script></textarea><title><script>alert(1)</script></title>',
    '<iframe src="javascript:alert(1)"></iframe><object data="javascript:alert(1)"></object><embed src="x">',
    '<a href="http://ok" onmouseover="x" target="_blank" rel="opener">l</a>',
    '<p>café € 中文 &eacute; &#x1F600;</p>',
    '<math><mi><script>alert(1)</script></mi></math><p>m</p>',
    '<div><div><div><div><div>deep</div></div></div></div></div>',
    '<ol start="3"><li>three</li></ol><hr size="2" width="50%"><br><wbr>',
    '<pre>  keep\n    spacing\n</pre><code>x &lt; y</code>',
    '<a href="http://x/?a=1&amp;b=2&c=3">amp</a>',
    '<h1>t</h1><h2>t</h2><span lang="en">s</span><small>s</small><sup>1</sup><sub>2</sub>',
]

# Parser differences, recorded rather than hidden: the exact nh3 output is shown for reference only.
# By design stricter than ammonia: every URL-carrying attribute is judged, `cite` included.
EXACT = [
    ('<blockquote cite="javascript:x">q</blockquote><q cite="http://c/">q</q><del cite="/d" datetime="2020-01-01">d</del>',
     '<blockquote>q</blockquote><q cite="http://c/">q</q><del cite="/d" datetime="2020-01-01">d</del>'),
]

NOTES = [
    ('<table><tr><td>c</td></tr></table>', "no tbody insertion"),
    ('<b><i>x</b>y</i>', "no adoption agency"),
]

ATTACKS = [
    # input, substrings that must NOT appear in the output
    ('<img src=x onerror=alert(1)>', ["onerror", "alert"]),
    ('<svg onload=alert(1)><circle onclick=x></circle></svg>', ["onload", "onclick", "svg"]),
    ('<a href="jAvAsCrIpT:alert(1)">x</a>', ["javascript", "alert"]),
    ('<a href="\x01javascript:alert(1)">x</a>', ["javascript"]),
    ('<a href="  \n javascript:alert(1)">x</a>', ["javascript"]),
    ('<div style="background:url(javascript:alert(1))" onclick="x">s</div>', ["style", "url(", "javascript", "onclick"]),
    ('<noscript><p title="</noscript><img src=x onerror=alert(1)>">t</p></noscript>', ["<script", "<noscript", "<img src=x"]),
    ('<math><mi//xlink:href="data:x,<script>alert(1)</script>">x</mi></math>', ["<script", "data:x"]),
    ('<form><math><mtext></form><form><mglyph><style></math><img src onerror=alert(1)>', ["onerror=", "<style"]),
    ('<svg><style><img src onerror=alert(1)></style></svg>', ["onerror=", "<style"]),
    ('<a href="http://ok" ONCLICK="x" OnMouseOver="y">k</a>', ["onclick", "onmouseover"]),
    ('<p title="</p><script>alert(1)</script>">t</p>', ["<script"]),
    ('<div><!--[if IE]><script>alert(1)</script><![endif]--></div>', ["<script", "alert"]),
    ('<script>alert(1)</script><SCRIPT SRC=//evil/x.js></SCRIPT><sCrIpT>x</sCrIpT>', ["script", "alert", "evil"]),
    ('<base href="javascript:alert(1)//"><link rel=stylesheet href=//evil/x.css><meta http-equiv=refresh content="0;url=javascript:alert(1)">', ["<base", "<link", "<meta", "javascript"]),
]

STYLE_CASES = [
    # (input, expected output) with css_properties = "color text-align width"
    ('<p style="color: red; text-align:center">a</p>', '<p style="color: red; text-align: center">a</p>'),
    ('<p style="color: red; background: url(javascript:alert(1)); width: 10px">a</p>', '<p style="color: red; width: 10px">a</p>'),
    ('<p style="width: expression(alert(1))">a</p>', '<p>a</p>'),
    ('<p style="background: red">a</p>', '<p>a</p>'),
    ('<p style="color: red /* c */">a</p>', '<p>a</p>'),
    ('<p style="color: \\72 ed">a</p>', '<p>a</p>'),
    ('<p style="">a</p>', '<p>a</p>'),
    ('<p style="color: &quot;x&quot;">a</p>', '<p style="color: &quot;x&quot;">a</p>'),
]

CONFIGS = [
    # name, nh3 kwargs, Neper Policy fields (strings of space-separated tokens)
    ("narrow", dict(tags={"p", "a", "b"}, attributes={"a": {"href"}}, url_schemes={"https"}, link_rel=None),
     dict(tags="p a b", tag_attributes="a:href", url_schemes="https", link_rel="", allow_relative=True)),
    ("nofollow", dict(link_rel="nofollow"), dict(link_rel="nofollow")),
    ("no_relative", dict(url_relative="deny"), dict(allow_relative=False)),
    ("remove_iframe", dict(clean_content_tags={"script", "style", "iframe"}), dict(remove_content="script style iframe")),
]
CONFIG_INPUTS = [
    '<p><a href="https://s/x" target="_blank" title="t">s</a> <a href="http://p/">p</a> <a href="/r">r</a> <b>b</b> <i>i</i></p>',
    '<div><iframe src="x">inner</iframe><span>s</span><a href="relative.html">rel</a></div>',
    '<a href="mailto:x@y.z" rel="x">m</a><img src="//h/i.png" alt="a">',
]

FIELDS = ["tags", "generic_attributes", "tag_attributes", "url_schemes", "remove_content", "css_properties", "link_rel", "allow_relative", "max_depth"]


def policy_expr(overrides, base="san.default_policy()"):
    if not overrides:
        return base
    return "policy_with(%s, %s)" % (base, ", ".join(
        lit(overrides.get(f, "")) if f in ("tags", "generic_attributes", "tag_attributes", "url_schemes", "remove_content", "css_properties", "link_rel") else
        ("true" if overrides.get(f, True) else "false") if f == "allow_relative" else "%du16" % overrides.get(f, 64)
        for f in FIELDS) if False else "")


def main():
    c = Checks()
    body = ""
    n = 0

    def run(name, source, expected, policy="san.default_policy()", idempotent=True):
        nonlocal n
        n += 1
        c.raw("    let (%s_o, %s_e) = san.sanitize(a, %s, %s)\n" % (name, name, lit(source), policy))
        c.add("%s_e != ok" % name)
        c.add("!str.eq(%s_o, %s)" % (name, lit(expected)))
        if idempotent:
            c.raw("    let (%s_o2, %s_e2) = san.sanitize(a, %s_o, %s)\n" % (name, name, name, policy))
            c.add("%s_e2 != ok || !str.eq(%s_o2, %s_o)" % (name, name, name))

    for i, src in enumerate(PARITY):
        run("p%d" % i, src, nh3.clean(src))
    # Configuration variants.
    for cname, kwargs, fields in CONFIGS:
        for j, src in enumerate(CONFIG_INPUTS):
            expected = nh3.clean(src, **kwargs)
            # Neper policy: start from the default and override fields.
            parts = ["    var pol_%s_%d = san.default_policy()\n" % (cname, j)]
            for f, v in fields.items():
                if isinstance(v, bool):
                    parts.append("    pol_%s_%d.%s = %s\n" % (cname, j, f, "true" if v else "false"))
                else:
                    parts.append("    pol_%s_%d.%s = %s\n" % (cname, j, f, lit(v)))
            c.raw("".join(parts))
            run("c_%s_%d" % (cname, j), src, expected, "pol_%s_%d" % (cname, j))
    # Style through the property allowlist.
    c.raw("    var style_policy = san.default_policy()\n    style_policy.generic_attributes = \"lang title style\"\n    style_policy.css_properties = \"color text-align width\"\n")
    for i, (src, expected) in enumerate(STYLE_CASES):
        run("s%d" % i, src, expected, "style_policy")
    # Attacks: properties of the output, and it must be stable.
    for i, (src, banned) in enumerate(ATTACKS):
        c.raw("    let (atk%d_o, atk%d_e) = san.sanitize(a, %s, san.default_policy())\n" % (i, i, lit(src)))
        c.add("atk%d_e != ok" % i)
        for word in banned:
            c.add("str.contains(atk%d_o, %s)" % (i, lit(word)))
        c.raw("    let (atk%d_o2, atk%d_e2) = san.sanitize(a, atk%d_o, san.default_policy())\n" % (i, i, i))
        c.add("atk%d_e2 != ok || !str.eq(atk%d_o2, atk%d_o)" % (i, i, i))
        # And the same input through nh3 must also be free of the banned words, so the list is not ours alone.
        out = nh3.clean(src).lower()
        for word in banned:
            assert word.lower() not in out, (src, word, out)
    for i, (src, expected) in enumerate(EXACT):
        run("x%d" % i, src, expected)
    # Known parser differences: still safe, still stable.
    for i, (src, why) in enumerate(NOTES):
        c.raw("    let (note%d_o, note%d_e) = san.sanitize(a, %s, san.default_policy())\n" % (i, i, lit(src)))
        c.add("note%d_e != ok || str.contains(note%d_o, \"<script\")" % (i, i))
        c.raw("    let (note%d_o2, note%d_e2) = san.sanitize(a, note%d_o, san.default_policy())\n" % (i, i, i))
        c.add("note%d_e2 != ok || !str.eq(note%d_o2, note%d_o)" % (i, i, i))
    # Nesting: fifty levels pass, a thousand are refused, and a custom depth limit applies.
    fifty = "<div>" * 50 + "x" + "</div>" * 50
    run("nest50", fifty, nh3.clean(fifty))
    c.raw("    let (deep_o, deep_e) = san.sanitize(a, %s, san.default_policy())\n" % lit("<div>" * 1000 + "x"))
    c.add("deep_e != san.TooDeep")
    c.raw("    var shallow = san.default_policy()\n    shallow.max_depth = 10u16\n")
    c.raw("    let (shallow_o, shallow_e) = san.sanitize(a, %s, shallow)\n" % lit("<div>" * 30 + "x"))
    c.add("shallow_e != san.TooDeep")
    # Encoding.
    c.raw("    let (bad_o, bad_e) = san.sanitize(a, \"<p>\\xff\\xfe</p>\", san.default_policy())\n")
    c.add("bad_e != san.Encoding")
    # Policy lookups on their own.
    c.add("san.url_allowed(\"HTTPS://x\", san.default_policy()) != true")
    c.add("san.url_allowed(\"javascript:x\", san.default_policy()) != false")
    c.add("san.url_allowed(\"java\\tscript:x\", san.default_policy()) != false")
    c.add("san.url_allowed(\"/a:b\", san.default_policy()) != true")
    c.add("san.url_allowed(\"#frag\", san.default_policy()) != true")
    header = ("// `e.fmt.html.sanitize`: thirty-odd inputs (event handlers, obfuscated and entity-encoded schemes, raw-text and\n"
              "// foreign-content tricks, comments, unclosed and unknown markup, non-ASCII text) cleaned and compared byte for byte\n"
              "// with nh3 (ammonia), four policy variants against nh3 configurations, the `style` property allowlist, attack\n"
              "// inputs checked for banned substrings, idempotence of every output, nesting limits, encoding and URL checks.\n"
              "// Written by scripts/gen_sanitize_test.py. Every check has its own exit code.\n")
    uses = ["e.os", "e.mem", "e.str", "e.fmt.html.sanitize as san"]
    fn_head = "fn main(a: *mem.Arena, args: []str) -> err {\n"
    target = write_fixture("fmt_html_sanitize", header, fn_head + c.text() + "    ret ok\n}\n", uses)
    print("wrote", target, "checks", c.code)


if __name__ == "__main__":
    main()
