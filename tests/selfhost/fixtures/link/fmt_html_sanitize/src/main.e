// `e.fmt.html.sanitize`: thirty-odd inputs (event handlers, obfuscated and entity-encoded schemes, raw-text and
// foreign-content tricks, comments, unclosed and unknown markup, non-ASCII text) cleaned and compared byte for byte
// with nh3 (ammonia), four policy variants against nh3 configurations, the `style` property allowlist, attack
// inputs checked for banned substrings, idempotence of every output, nesting limits, encoding and URL checks.
// Written by scripts/gen_sanitize_test.py. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.html.sanitize as san

fn main(a: *mem.Arena, args: []str) -> err {
    let (p0_o, p0_e) = san.sanitize(a, "<p onclick=x>hi<script>1</script><a href=\"javascript:1\">a</a><a href=\"http://x\">b</a></p>", san.default_policy())
    if p0_e != ok { os.exit(1) }
    if !str.eq(p0_o, "<p>hi<a rel=\"noopener noreferrer\">a</a><a href=\"http://x\" rel=\"noopener noreferrer\">b</a></p>") { os.exit(2) }
    let (p0_o2, p0_e2) = san.sanitize(a, p0_o, san.default_policy())
    if p0_e2 != ok || !str.eq(p0_o2, p0_o) { os.exit(3) }
    let (p1_o, p1_e) = san.sanitize(a, "<div><b>bold</b> &amp; <i>it</i> &lt;x&gt; \"q\" \xc2\xa0nb</div>", san.default_policy())
    if p1_e != ok { os.exit(4) }
    if !str.eq(p1_o, "<div><b>bold</b> &amp; <i>it</i> &lt;x&gt; \"q\" &nbsp;nb</div>") { os.exit(5) }
    let (p1_o2, p1_e2) = san.sanitize(a, p1_o, san.default_policy())
    if p1_e2 != ok || !str.eq(p1_o2, p1_o) { os.exit(6) }
    let (p2_o, p2_e) = san.sanitize(a, "<a href=\"  JaVa\x09ScRiPt:alert(1)\">x</a>", san.default_policy())
    if p2_e != ok { os.exit(7) }
    if !str.eq(p2_o, "<a rel=\"noopener noreferrer\">x</a>") { os.exit(8) }
    let (p2_o2, p2_e2) = san.sanitize(a, p2_o, san.default_policy())
    if p2_e2 != ok || !str.eq(p2_o2, p2_o) { os.exit(9) }
    let (p3_o, p3_e) = san.sanitize(a, "<a href=\"http://a.b/?q=1&x=2\" title=\"t &quot;q&quot; <z>\">l</a>", san.default_policy())
    if p3_e != ok { os.exit(10) }
    if !str.eq(p3_o, "<a href=\"http://a.b/?q=1&amp;x=2\" title=\"t &quot;q&quot; &lt;z&gt;\" rel=\"noopener noreferrer\">l</a>") { os.exit(11) }
    let (p3_o2, p3_e2) = san.sanitize(a, p3_o, san.default_policy())
    if p3_e2 != ok || !str.eq(p3_o2, p3_o) { os.exit(12) }
    let (p4_o, p4_e) = san.sanitize(a, "<img src=\"x\" onerror=\"alert(1)\"><p>after", san.default_policy())
    if p4_e != ok { os.exit(13) }
    if !str.eq(p4_o, "<img src=\"x\"><p>after</p>") { os.exit(14) }
    let (p4_o2, p4_e2) = san.sanitize(a, p4_o, san.default_policy())
    if p4_e2 != ok || !str.eq(p4_o2, p4_o) { os.exit(15) }
    let (p5_o, p5_e) = san.sanitize(a, "<style>p{}</style><p style=\"color:red\">s</p>", san.default_policy())
    if p5_e != ok { os.exit(16) }
    if !str.eq(p5_o, "<p>s</p>") { os.exit(17) }
    let (p5_o2, p5_e2) = san.sanitize(a, p5_o, san.default_policy())
    if p5_e2 != ok || !str.eq(p5_o2, p5_o) { os.exit(18) }
    let (p6_o, p6_e) = san.sanitize(a, "<ul><li>a<li>b</ul>", san.default_policy())
    if p6_e != ok { os.exit(19) }
    if !str.eq(p6_o, "<ul><li>a</li><li>b</li></ul>") { os.exit(20) }
    let (p6_o2, p6_e2) = san.sanitize(a, p6_o, san.default_policy())
    if p6_e2 != ok || !str.eq(p6_o2, p6_o) { os.exit(21) }
    let (p7_o, p7_e) = san.sanitize(a, "<table><tbody><tr><td colspan=\"2\" onclick=\"x\">c</td></tr></tbody></table>", san.default_policy())
    if p7_e != ok { os.exit(22) }
    if !str.eq(p7_o, "<table><tbody><tr><td colspan=\"2\">c</td></tr></tbody></table>") { os.exit(23) }
    let (p7_o2, p7_e2) = san.sanitize(a, p7_o, san.default_policy())
    if p7_e2 != ok || !str.eq(p7_o2, p7_o) { os.exit(24) }
    let (p8_o, p8_e) = san.sanitize(a, "<svg><script>alert(1)</script></svg><p>t", san.default_policy())
    if p8_e != ok { os.exit(25) }
    if !str.eq(p8_o, "<p>t</p>") { os.exit(26) }
    let (p8_o2, p8_e2) = san.sanitize(a, p8_o, san.default_policy())
    if p8_e2 != ok || !str.eq(p8_o2, p8_o) { os.exit(27) }
    let (p9_o, p9_e) = san.sanitize(a, "<!-- c --><p>x</p>", san.default_policy())
    if p9_e != ok { os.exit(28) }
    if !str.eq(p9_o, "<p>x</p>") { os.exit(29) }
    let (p9_o2, p9_e2) = san.sanitize(a, p9_o, san.default_policy())
    if p9_e2 != ok || !str.eq(p9_o2, p9_o) { os.exit(30) }
    let (p10_o, p10_e) = san.sanitize(a, "<html><head><title>T</title></head><body>b</body></html>", san.default_policy())
    if p10_e != ok { os.exit(31) }
    if !str.eq(p10_o, "Tb") { os.exit(32) }
    let (p10_o2, p10_e2) = san.sanitize(a, p10_o, san.default_policy())
    if p10_e2 != ok || !str.eq(p10_o2, p10_o) { os.exit(33) }
    let (p11_o, p11_e) = san.sanitize(a, "<form action=\"x\"><input value=1>t</form>", san.default_policy())
    if p11_e != ok { os.exit(34) }
    if !str.eq(p11_o, "t") { os.exit(35) }
    let (p11_o2, p11_e2) = san.sanitize(a, p11_o, san.default_policy())
    if p11_e2 != ok || !str.eq(p11_o2, p11_o) { os.exit(36) }
    let (p12_o, p12_e) = san.sanitize(a, "<a href=\"mailto:a@b.c\">m</a><a href=\"//evil.com/x\">r</a><a href=\"/rel\">rel</a><a href=\"ftp://h\">ftp</a>", san.default_policy())
    if p12_e != ok { os.exit(37) }
    if !str.eq(p12_o, "<a href=\"mailto:a@b.c\" rel=\"noopener noreferrer\">m</a><a href=\"//evil.com/x\" rel=\"noopener noreferrer\">r</a><a href=\"/rel\" rel=\"noopener noreferrer\">rel</a><a href=\"ftp://h\" rel=\"noopener noreferrer\">ftp</a>") { os.exit(38) }
    let (p12_o2, p12_e2) = san.sanitize(a, p12_o, san.default_policy())
    if p12_e2 != ok || !str.eq(p12_o2, p12_o) { os.exit(39) }
    let (p13_o, p13_e) = san.sanitize(a, "<p>unclosed <em>em", san.default_policy())
    if p13_e != ok { os.exit(40) }
    if !str.eq(p13_o, "<p>unclosed <em>em</em></p>") { os.exit(41) }
    let (p13_o2, p13_e2) = san.sanitize(a, p13_o, san.default_policy())
    if p13_e2 != ok || !str.eq(p13_o2, p13_o) { os.exit(42) }
    let (p14_o, p14_e) = san.sanitize(a, "plain & text < 3", san.default_policy())
    if p14_e != ok { os.exit(43) }
    if !str.eq(p14_o, "plain &amp; text &lt; 3") { os.exit(44) }
    let (p14_o2, p14_e2) = san.sanitize(a, p14_o, san.default_policy())
    if p14_e2 != ok || !str.eq(p14_o2, p14_o) { os.exit(45) }
    let (p15_o, p15_e) = san.sanitize(a, "<A HREF=\"HTTP://UP.CASE/\" TITLE=\"T\">Up</A><BR><IMG SRC=\"a.png\" ALT=\"x\" WIDTH=10>", san.default_policy())
    if p15_e != ok { os.exit(46) }
    if !str.eq(p15_o, "<a href=\"HTTP://UP.CASE/\" title=\"T\" rel=\"noopener noreferrer\">Up</a><br><img src=\"a.png\" alt=\"x\" width=\"10\">") { os.exit(47) }
    let (p15_o2, p15_e2) = san.sanitize(a, p15_o, san.default_policy())
    if p15_e2 != ok || !str.eq(p15_o2, p15_o) { os.exit(48) }
    let (p16_o, p16_e) = san.sanitize(a, "<a href=\"&#106;avascript:alert(1)\">e</a><a href=\"java&#9;script:alert(1)\">t</a><a href=\"&#x6A;avascript&colon;alert(1)\">c</a>", san.default_policy())
    if p16_e != ok { os.exit(49) }
    if !str.eq(p16_o, "<a rel=\"noopener noreferrer\">e</a><a rel=\"noopener noreferrer\">t</a><a rel=\"noopener noreferrer\">c</a>") { os.exit(50) }
    let (p16_o2, p16_e2) = san.sanitize(a, p16_o, san.default_policy())
    if p16_e2 != ok || !str.eq(p16_o2, p16_o) { os.exit(51) }
    let (p17_o, p17_e) = san.sanitize(a, "<a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==\">d</a><a href=\"vbscript:msgbox(1)\">v</a>", san.default_policy())
    if p17_e != ok { os.exit(52) }
    if !str.eq(p17_o, "<a rel=\"noopener noreferrer\">d</a><a rel=\"noopener noreferrer\">v</a>") { os.exit(53) }
    let (p17_o2, p17_e2) = san.sanitize(a, p17_o, san.default_policy())
    if p17_e2 != ok || !str.eq(p17_o2, p17_o) { os.exit(54) }
    let (p18_o, p18_e) = san.sanitize(a, "<img src=\"javascript:alert(1)\"><img src=\"data:image/png;base64,AAAA\"><img src=\"https://ok/x.png\">", san.default_policy())
    if p18_e != ok { os.exit(55) }
    if !str.eq(p18_o, "<img><img><img src=\"https://ok/x.png\">") { os.exit(56) }
    let (p18_o2, p18_e2) = san.sanitize(a, p18_o, san.default_policy())
    if p18_e2 != ok || !str.eq(p18_o2, p18_o) { os.exit(57) }
    let (p19_o, p19_e) = san.sanitize(a, "<body onload=alert(1)><div onmouseover=\"x\" lang=\"fr\" title=\"t\" id=\"i\" class=\"c\" data-x=\"1\">d</div></body>", san.default_policy())
    if p19_e != ok { os.exit(58) }
    if !str.eq(p19_o, "<div lang=\"fr\" title=\"t\">d</div>") { os.exit(59) }
    let (p19_o2, p19_e2) = san.sanitize(a, p19_o, san.default_policy())
    if p19_e2 != ok || !str.eq(p19_o2, p19_o) { os.exit(60) }
    let (p20_o, p20_e) = san.sanitize(a, "<scr<script>ipt>alert(1)</scr</script>ipt>", san.default_policy())
    if p20_e != ok { os.exit(61) }
    if !str.eq(p20_o, "ipt&gt;alert(1)ipt&gt;") { os.exit(62) }
    let (p20_o2, p20_e2) = san.sanitize(a, p20_o, san.default_policy())
    if p20_e2 != ok || !str.eq(p20_o2, p20_o) { os.exit(63) }
    let (p21_o, p21_e) = san.sanitize(a, "<<script>alert(1);//<</script>", san.default_policy())
    if p21_e != ok { os.exit(64) }
    if !str.eq(p21_o, "&lt;") { os.exit(65) }
    let (p21_o2, p21_e2) = san.sanitize(a, p21_o, san.default_policy())
    if p21_e2 != ok || !str.eq(p21_o2, p21_o) { os.exit(66) }
    let (p22_o, p22_e) = san.sanitize(a, "<textarea><script>alert(1)</script></textarea><title><script>alert(1)</script></title>", san.default_policy())
    if p22_e != ok { os.exit(67) }
    if !str.eq(p22_o, "&lt;script&gt;alert(1)&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;") { os.exit(68) }
    let (p22_o2, p22_e2) = san.sanitize(a, p22_o, san.default_policy())
    if p22_e2 != ok || !str.eq(p22_o2, p22_o) { os.exit(69) }
    let (p23_o, p23_e) = san.sanitize(a, "<iframe src=\"javascript:alert(1)\"></iframe><object data=\"javascript:alert(1)\"></object><embed src=\"x\">", san.default_policy())
    if p23_e != ok { os.exit(70) }
    if !str.eq(p23_o, "") { os.exit(71) }
    let (p23_o2, p23_e2) = san.sanitize(a, p23_o, san.default_policy())
    if p23_e2 != ok || !str.eq(p23_o2, p23_o) { os.exit(72) }
    let (p24_o, p24_e) = san.sanitize(a, "<a href=\"http://ok\" onmouseover=\"x\" target=\"_blank\" rel=\"opener\">l</a>", san.default_policy())
    if p24_e != ok { os.exit(73) }
    if !str.eq(p24_o, "<a href=\"http://ok\" rel=\"noopener noreferrer\">l</a>") { os.exit(74) }
    let (p24_o2, p24_e2) = san.sanitize(a, p24_o, san.default_policy())
    if p24_e2 != ok || !str.eq(p24_o2, p24_o) { os.exit(75) }
    let (p25_o, p25_e) = san.sanitize(a, "<p>caf\xc3\xa9 \xe2\x82\xac \xe4\xb8\xad\xe6\x96\x87 &eacute; &#x1F600;</p>", san.default_policy())
    if p25_e != ok { os.exit(76) }
    if !str.eq(p25_o, "<p>caf\xc3\xa9 \xe2\x82\xac \xe4\xb8\xad\xe6\x96\x87 \xc3\xa9 \xf0\x9f\x98\x80</p>") { os.exit(77) }
    let (p25_o2, p25_e2) = san.sanitize(a, p25_o, san.default_policy())
    if p25_e2 != ok || !str.eq(p25_o2, p25_o) { os.exit(78) }
    let (p26_o, p26_e) = san.sanitize(a, "<math><mi><script>alert(1)</script></mi></math><p>m</p>", san.default_policy())
    if p26_e != ok { os.exit(79) }
    if !str.eq(p26_o, "<p>m</p>") { os.exit(80) }
    let (p26_o2, p26_e2) = san.sanitize(a, p26_o, san.default_policy())
    if p26_e2 != ok || !str.eq(p26_o2, p26_o) { os.exit(81) }
    let (p27_o, p27_e) = san.sanitize(a, "<div><div><div><div><div>deep</div></div></div></div></div>", san.default_policy())
    if p27_e != ok { os.exit(82) }
    if !str.eq(p27_o, "<div><div><div><div><div>deep</div></div></div></div></div>") { os.exit(83) }
    let (p27_o2, p27_e2) = san.sanitize(a, p27_o, san.default_policy())
    if p27_e2 != ok || !str.eq(p27_o2, p27_o) { os.exit(84) }
    let (p28_o, p28_e) = san.sanitize(a, "<ol start=\"3\"><li>three</li></ol><hr size=\"2\" width=\"50%\"><br><wbr>", san.default_policy())
    if p28_e != ok { os.exit(85) }
    if !str.eq(p28_o, "<ol start=\"3\"><li>three</li></ol><hr size=\"2\" width=\"50%\"><br><wbr>") { os.exit(86) }
    let (p28_o2, p28_e2) = san.sanitize(a, p28_o, san.default_policy())
    if p28_e2 != ok || !str.eq(p28_o2, p28_o) { os.exit(87) }
    let (p29_o, p29_e) = san.sanitize(a, "<pre>  keep\x0a    spacing\x0a</pre><code>x &lt; y</code>", san.default_policy())
    if p29_e != ok { os.exit(88) }
    if !str.eq(p29_o, "<pre>  keep\x0a    spacing\x0a</pre><code>x &lt; y</code>") { os.exit(89) }
    let (p29_o2, p29_e2) = san.sanitize(a, p29_o, san.default_policy())
    if p29_e2 != ok || !str.eq(p29_o2, p29_o) { os.exit(90) }
    let (p30_o, p30_e) = san.sanitize(a, "<a href=\"http://x/?a=1&amp;b=2&c=3\">amp</a>", san.default_policy())
    if p30_e != ok { os.exit(91) }
    if !str.eq(p30_o, "<a href=\"http://x/?a=1&amp;b=2&amp;c=3\" rel=\"noopener noreferrer\">amp</a>") { os.exit(92) }
    let (p30_o2, p30_e2) = san.sanitize(a, p30_o, san.default_policy())
    if p30_e2 != ok || !str.eq(p30_o2, p30_o) { os.exit(93) }
    let (p31_o, p31_e) = san.sanitize(a, "<h1>t</h1><h2>t</h2><span lang=\"en\">s</span><small>s</small><sup>1</sup><sub>2</sub>", san.default_policy())
    if p31_e != ok { os.exit(94) }
    if !str.eq(p31_o, "<h1>t</h1><h2>t</h2><span lang=\"en\">s</span><small>s</small><sup>1</sup><sub>2</sub>") { os.exit(95) }
    let (p31_o2, p31_e2) = san.sanitize(a, p31_o, san.default_policy())
    if p31_e2 != ok || !str.eq(p31_o2, p31_o) { os.exit(96) }
    var pol_narrow_0 = san.default_policy()
    pol_narrow_0.tags = "p a b"
    pol_narrow_0.tag_attributes = "a:href"
    pol_narrow_0.url_schemes = "https"
    pol_narrow_0.link_rel = ""
    pol_narrow_0.allow_relative = true
    let (c_narrow_0_o, c_narrow_0_e) = san.sanitize(a, "<p><a href=\"https://s/x\" target=\"_blank\" title=\"t\">s</a> <a href=\"http://p/\">p</a> <a href=\"/r\">r</a> <b>b</b> <i>i</i></p>", pol_narrow_0)
    if c_narrow_0_e != ok { os.exit(97) }
    if !str.eq(c_narrow_0_o, "<p><a href=\"https://s/x\" title=\"t\">s</a> <a>p</a> <a href=\"/r\">r</a> <b>b</b> i</p>") { os.exit(98) }
    let (c_narrow_0_o2, c_narrow_0_e2) = san.sanitize(a, c_narrow_0_o, pol_narrow_0)
    if c_narrow_0_e2 != ok || !str.eq(c_narrow_0_o2, c_narrow_0_o) { os.exit(99) }
    var pol_narrow_1 = san.default_policy()
    pol_narrow_1.tags = "p a b"
    pol_narrow_1.tag_attributes = "a:href"
    pol_narrow_1.url_schemes = "https"
    pol_narrow_1.link_rel = ""
    pol_narrow_1.allow_relative = true
    let (c_narrow_1_o, c_narrow_1_e) = san.sanitize(a, "<div><iframe src=\"x\">inner</iframe><span>s</span><a href=\"relative.html\">rel</a></div>", pol_narrow_1)
    if c_narrow_1_e != ok { os.exit(100) }
    if !str.eq(c_narrow_1_o, "inners<a href=\"relative.html\">rel</a>") { os.exit(101) }
    let (c_narrow_1_o2, c_narrow_1_e2) = san.sanitize(a, c_narrow_1_o, pol_narrow_1)
    if c_narrow_1_e2 != ok || !str.eq(c_narrow_1_o2, c_narrow_1_o) { os.exit(102) }
    var pol_narrow_2 = san.default_policy()
    pol_narrow_2.tags = "p a b"
    pol_narrow_2.tag_attributes = "a:href"
    pol_narrow_2.url_schemes = "https"
    pol_narrow_2.link_rel = ""
    pol_narrow_2.allow_relative = true
    let (c_narrow_2_o, c_narrow_2_e) = san.sanitize(a, "<a href=\"mailto:x@y.z\" rel=\"x\">m</a><img src=\"//h/i.png\" alt=\"a\">", pol_narrow_2)
    if c_narrow_2_e != ok { os.exit(103) }
    if !str.eq(c_narrow_2_o, "<a>m</a>") { os.exit(104) }
    let (c_narrow_2_o2, c_narrow_2_e2) = san.sanitize(a, c_narrow_2_o, pol_narrow_2)
    if c_narrow_2_e2 != ok || !str.eq(c_narrow_2_o2, c_narrow_2_o) { os.exit(105) }
    var pol_nofollow_0 = san.default_policy()
    pol_nofollow_0.link_rel = "nofollow"
    let (c_nofollow_0_o, c_nofollow_0_e) = san.sanitize(a, "<p><a href=\"https://s/x\" target=\"_blank\" title=\"t\">s</a> <a href=\"http://p/\">p</a> <a href=\"/r\">r</a> <b>b</b> <i>i</i></p>", pol_nofollow_0)
    if c_nofollow_0_e != ok { os.exit(106) }
    if !str.eq(c_nofollow_0_o, "<p><a href=\"https://s/x\" title=\"t\" rel=\"nofollow\">s</a> <a href=\"http://p/\" rel=\"nofollow\">p</a> <a href=\"/r\" rel=\"nofollow\">r</a> <b>b</b> <i>i</i></p>") { os.exit(107) }
    let (c_nofollow_0_o2, c_nofollow_0_e2) = san.sanitize(a, c_nofollow_0_o, pol_nofollow_0)
    if c_nofollow_0_e2 != ok || !str.eq(c_nofollow_0_o2, c_nofollow_0_o) { os.exit(108) }
    var pol_nofollow_1 = san.default_policy()
    pol_nofollow_1.link_rel = "nofollow"
    let (c_nofollow_1_o, c_nofollow_1_e) = san.sanitize(a, "<div><iframe src=\"x\">inner</iframe><span>s</span><a href=\"relative.html\">rel</a></div>", pol_nofollow_1)
    if c_nofollow_1_e != ok { os.exit(109) }
    if !str.eq(c_nofollow_1_o, "<div>inner<span>s</span><a href=\"relative.html\" rel=\"nofollow\">rel</a></div>") { os.exit(110) }
    let (c_nofollow_1_o2, c_nofollow_1_e2) = san.sanitize(a, c_nofollow_1_o, pol_nofollow_1)
    if c_nofollow_1_e2 != ok || !str.eq(c_nofollow_1_o2, c_nofollow_1_o) { os.exit(111) }
    var pol_nofollow_2 = san.default_policy()
    pol_nofollow_2.link_rel = "nofollow"
    let (c_nofollow_2_o, c_nofollow_2_e) = san.sanitize(a, "<a href=\"mailto:x@y.z\" rel=\"x\">m</a><img src=\"//h/i.png\" alt=\"a\">", pol_nofollow_2)
    if c_nofollow_2_e != ok { os.exit(112) }
    if !str.eq(c_nofollow_2_o, "<a href=\"mailto:x@y.z\" rel=\"nofollow\">m</a><img src=\"//h/i.png\" alt=\"a\">") { os.exit(113) }
    let (c_nofollow_2_o2, c_nofollow_2_e2) = san.sanitize(a, c_nofollow_2_o, pol_nofollow_2)
    if c_nofollow_2_e2 != ok || !str.eq(c_nofollow_2_o2, c_nofollow_2_o) { os.exit(114) }
    var pol_no_relative_0 = san.default_policy()
    pol_no_relative_0.allow_relative = false
    let (c_no_relative_0_o, c_no_relative_0_e) = san.sanitize(a, "<p><a href=\"https://s/x\" target=\"_blank\" title=\"t\">s</a> <a href=\"http://p/\">p</a> <a href=\"/r\">r</a> <b>b</b> <i>i</i></p>", pol_no_relative_0)
    if c_no_relative_0_e != ok { os.exit(115) }
    if !str.eq(c_no_relative_0_o, "<p><a href=\"https://s/x\" title=\"t\" rel=\"noopener noreferrer\">s</a> <a href=\"http://p/\" rel=\"noopener noreferrer\">p</a> <a rel=\"noopener noreferrer\">r</a> <b>b</b> <i>i</i></p>") { os.exit(116) }
    let (c_no_relative_0_o2, c_no_relative_0_e2) = san.sanitize(a, c_no_relative_0_o, pol_no_relative_0)
    if c_no_relative_0_e2 != ok || !str.eq(c_no_relative_0_o2, c_no_relative_0_o) { os.exit(117) }
    var pol_no_relative_1 = san.default_policy()
    pol_no_relative_1.allow_relative = false
    let (c_no_relative_1_o, c_no_relative_1_e) = san.sanitize(a, "<div><iframe src=\"x\">inner</iframe><span>s</span><a href=\"relative.html\">rel</a></div>", pol_no_relative_1)
    if c_no_relative_1_e != ok { os.exit(118) }
    if !str.eq(c_no_relative_1_o, "<div>inner<span>s</span><a rel=\"noopener noreferrer\">rel</a></div>") { os.exit(119) }
    let (c_no_relative_1_o2, c_no_relative_1_e2) = san.sanitize(a, c_no_relative_1_o, pol_no_relative_1)
    if c_no_relative_1_e2 != ok || !str.eq(c_no_relative_1_o2, c_no_relative_1_o) { os.exit(120) }
    var pol_no_relative_2 = san.default_policy()
    pol_no_relative_2.allow_relative = false
    let (c_no_relative_2_o, c_no_relative_2_e) = san.sanitize(a, "<a href=\"mailto:x@y.z\" rel=\"x\">m</a><img src=\"//h/i.png\" alt=\"a\">", pol_no_relative_2)
    if c_no_relative_2_e != ok { os.exit(121) }
    if !str.eq(c_no_relative_2_o, "<a href=\"mailto:x@y.z\" rel=\"noopener noreferrer\">m</a><img alt=\"a\">") { os.exit(122) }
    let (c_no_relative_2_o2, c_no_relative_2_e2) = san.sanitize(a, c_no_relative_2_o, pol_no_relative_2)
    if c_no_relative_2_e2 != ok || !str.eq(c_no_relative_2_o2, c_no_relative_2_o) { os.exit(123) }
    var pol_remove_iframe_0 = san.default_policy()
    pol_remove_iframe_0.remove_content = "script style iframe"
    let (c_remove_iframe_0_o, c_remove_iframe_0_e) = san.sanitize(a, "<p><a href=\"https://s/x\" target=\"_blank\" title=\"t\">s</a> <a href=\"http://p/\">p</a> <a href=\"/r\">r</a> <b>b</b> <i>i</i></p>", pol_remove_iframe_0)
    if c_remove_iframe_0_e != ok { os.exit(124) }
    if !str.eq(c_remove_iframe_0_o, "<p><a href=\"https://s/x\" title=\"t\" rel=\"noopener noreferrer\">s</a> <a href=\"http://p/\" rel=\"noopener noreferrer\">p</a> <a href=\"/r\" rel=\"noopener noreferrer\">r</a> <b>b</b> <i>i</i></p>") { os.exit(125) }
    let (c_remove_iframe_0_o2, c_remove_iframe_0_e2) = san.sanitize(a, c_remove_iframe_0_o, pol_remove_iframe_0)
    if c_remove_iframe_0_e2 != ok || !str.eq(c_remove_iframe_0_o2, c_remove_iframe_0_o) { os.exit(126) }
    var pol_remove_iframe_1 = san.default_policy()
    pol_remove_iframe_1.remove_content = "script style iframe"
    let (c_remove_iframe_1_o, c_remove_iframe_1_e) = san.sanitize(a, "<div><iframe src=\"x\">inner</iframe><span>s</span><a href=\"relative.html\">rel</a></div>", pol_remove_iframe_1)
    if c_remove_iframe_1_e != ok { os.exit(127) }
    if !str.eq(c_remove_iframe_1_o, "<div><span>s</span><a href=\"relative.html\" rel=\"noopener noreferrer\">rel</a></div>") { os.exit(128) }
    let (c_remove_iframe_1_o2, c_remove_iframe_1_e2) = san.sanitize(a, c_remove_iframe_1_o, pol_remove_iframe_1)
    if c_remove_iframe_1_e2 != ok || !str.eq(c_remove_iframe_1_o2, c_remove_iframe_1_o) { os.exit(129) }
    var pol_remove_iframe_2 = san.default_policy()
    pol_remove_iframe_2.remove_content = "script style iframe"
    let (c_remove_iframe_2_o, c_remove_iframe_2_e) = san.sanitize(a, "<a href=\"mailto:x@y.z\" rel=\"x\">m</a><img src=\"//h/i.png\" alt=\"a\">", pol_remove_iframe_2)
    if c_remove_iframe_2_e != ok { os.exit(130) }
    if !str.eq(c_remove_iframe_2_o, "<a href=\"mailto:x@y.z\" rel=\"noopener noreferrer\">m</a><img src=\"//h/i.png\" alt=\"a\">") { os.exit(131) }
    let (c_remove_iframe_2_o2, c_remove_iframe_2_e2) = san.sanitize(a, c_remove_iframe_2_o, pol_remove_iframe_2)
    if c_remove_iframe_2_e2 != ok || !str.eq(c_remove_iframe_2_o2, c_remove_iframe_2_o) { os.exit(132) }
    var style_policy = san.default_policy()
    style_policy.generic_attributes = "lang title style"
    style_policy.css_properties = "color text-align width"
    let (s0_o, s0_e) = san.sanitize(a, "<p style=\"color: red; text-align:center\">a</p>", style_policy)
    if s0_e != ok { os.exit(133) }
    if !str.eq(s0_o, "<p style=\"color: red; text-align: center\">a</p>") { os.exit(134) }
    let (s0_o2, s0_e2) = san.sanitize(a, s0_o, style_policy)
    if s0_e2 != ok || !str.eq(s0_o2, s0_o) { os.exit(135) }
    let (s1_o, s1_e) = san.sanitize(a, "<p style=\"color: red; background: url(javascript:alert(1)); width: 10px\">a</p>", style_policy)
    if s1_e != ok { os.exit(136) }
    if !str.eq(s1_o, "<p style=\"color: red; width: 10px\">a</p>") { os.exit(137) }
    let (s1_o2, s1_e2) = san.sanitize(a, s1_o, style_policy)
    if s1_e2 != ok || !str.eq(s1_o2, s1_o) { os.exit(138) }
    let (s2_o, s2_e) = san.sanitize(a, "<p style=\"width: expression(alert(1))\">a</p>", style_policy)
    if s2_e != ok { os.exit(139) }
    if !str.eq(s2_o, "<p>a</p>") { os.exit(140) }
    let (s2_o2, s2_e2) = san.sanitize(a, s2_o, style_policy)
    if s2_e2 != ok || !str.eq(s2_o2, s2_o) { os.exit(141) }
    let (s3_o, s3_e) = san.sanitize(a, "<p style=\"background: red\">a</p>", style_policy)
    if s3_e != ok { os.exit(142) }
    if !str.eq(s3_o, "<p>a</p>") { os.exit(143) }
    let (s3_o2, s3_e2) = san.sanitize(a, s3_o, style_policy)
    if s3_e2 != ok || !str.eq(s3_o2, s3_o) { os.exit(144) }
    let (s4_o, s4_e) = san.sanitize(a, "<p style=\"color: red /* c */\">a</p>", style_policy)
    if s4_e != ok { os.exit(145) }
    if !str.eq(s4_o, "<p>a</p>") { os.exit(146) }
    let (s4_o2, s4_e2) = san.sanitize(a, s4_o, style_policy)
    if s4_e2 != ok || !str.eq(s4_o2, s4_o) { os.exit(147) }
    let (s5_o, s5_e) = san.sanitize(a, "<p style=\"color: \\72 ed\">a</p>", style_policy)
    if s5_e != ok { os.exit(148) }
    if !str.eq(s5_o, "<p>a</p>") { os.exit(149) }
    let (s5_o2, s5_e2) = san.sanitize(a, s5_o, style_policy)
    if s5_e2 != ok || !str.eq(s5_o2, s5_o) { os.exit(150) }
    let (s6_o, s6_e) = san.sanitize(a, "<p style=\"\">a</p>", style_policy)
    if s6_e != ok { os.exit(151) }
    if !str.eq(s6_o, "<p>a</p>") { os.exit(152) }
    let (s6_o2, s6_e2) = san.sanitize(a, s6_o, style_policy)
    if s6_e2 != ok || !str.eq(s6_o2, s6_o) { os.exit(153) }
    let (s7_o, s7_e) = san.sanitize(a, "<p style=\"color: &quot;x&quot;\">a</p>", style_policy)
    if s7_e != ok { os.exit(154) }
    if !str.eq(s7_o, "<p style=\"color: &quot;x&quot;\">a</p>") { os.exit(155) }
    let (s7_o2, s7_e2) = san.sanitize(a, s7_o, style_policy)
    if s7_e2 != ok || !str.eq(s7_o2, s7_o) { os.exit(156) }
    let (atk0_o, atk0_e) = san.sanitize(a, "<img src=x onerror=alert(1)>", san.default_policy())
    if atk0_e != ok { os.exit(157) }
    if str.contains(atk0_o, "onerror") { os.exit(158) }
    if str.contains(atk0_o, "alert") { os.exit(159) }
    let (atk0_o2, atk0_e2) = san.sanitize(a, atk0_o, san.default_policy())
    if atk0_e2 != ok || !str.eq(atk0_o2, atk0_o) { os.exit(160) }
    let (atk1_o, atk1_e) = san.sanitize(a, "<svg onload=alert(1)><circle onclick=x></circle></svg>", san.default_policy())
    if atk1_e != ok { os.exit(161) }
    if str.contains(atk1_o, "onload") { os.exit(162) }
    if str.contains(atk1_o, "onclick") { os.exit(163) }
    if str.contains(atk1_o, "svg") { os.exit(164) }
    let (atk1_o2, atk1_e2) = san.sanitize(a, atk1_o, san.default_policy())
    if atk1_e2 != ok || !str.eq(atk1_o2, atk1_o) { os.exit(165) }
    let (atk2_o, atk2_e) = san.sanitize(a, "<a href=\"jAvAsCrIpT:alert(1)\">x</a>", san.default_policy())
    if atk2_e != ok { os.exit(166) }
    if str.contains(atk2_o, "javascript") { os.exit(167) }
    if str.contains(atk2_o, "alert") { os.exit(168) }
    let (atk2_o2, atk2_e2) = san.sanitize(a, atk2_o, san.default_policy())
    if atk2_e2 != ok || !str.eq(atk2_o2, atk2_o) { os.exit(169) }
    let (atk3_o, atk3_e) = san.sanitize(a, "<a href=\"\x01javascript:alert(1)\">x</a>", san.default_policy())
    if atk3_e != ok { os.exit(170) }
    if str.contains(atk3_o, "javascript") { os.exit(171) }
    let (atk3_o2, atk3_e2) = san.sanitize(a, atk3_o, san.default_policy())
    if atk3_e2 != ok || !str.eq(atk3_o2, atk3_o) { os.exit(172) }
    let (atk4_o, atk4_e) = san.sanitize(a, "<a href=\"  \x0a javascript:alert(1)\">x</a>", san.default_policy())
    if atk4_e != ok { os.exit(173) }
    if str.contains(atk4_o, "javascript") { os.exit(174) }
    let (atk4_o2, atk4_e2) = san.sanitize(a, atk4_o, san.default_policy())
    if atk4_e2 != ok || !str.eq(atk4_o2, atk4_o) { os.exit(175) }
    let (atk5_o, atk5_e) = san.sanitize(a, "<div style=\"background:url(javascript:alert(1))\" onclick=\"x\">s</div>", san.default_policy())
    if atk5_e != ok { os.exit(176) }
    if str.contains(atk5_o, "style") { os.exit(177) }
    if str.contains(atk5_o, "url(") { os.exit(178) }
    if str.contains(atk5_o, "javascript") { os.exit(179) }
    if str.contains(atk5_o, "onclick") { os.exit(180) }
    let (atk5_o2, atk5_e2) = san.sanitize(a, atk5_o, san.default_policy())
    if atk5_e2 != ok || !str.eq(atk5_o2, atk5_o) { os.exit(181) }
    let (atk6_o, atk6_e) = san.sanitize(a, "<noscript><p title=\"</noscript><img src=x onerror=alert(1)>\">t</p></noscript>", san.default_policy())
    if atk6_e != ok { os.exit(182) }
    if str.contains(atk6_o, "<script") { os.exit(183) }
    if str.contains(atk6_o, "<noscript") { os.exit(184) }
    if str.contains(atk6_o, "<img src=x") { os.exit(185) }
    let (atk6_o2, atk6_e2) = san.sanitize(a, atk6_o, san.default_policy())
    if atk6_e2 != ok || !str.eq(atk6_o2, atk6_o) { os.exit(186) }
    let (atk7_o, atk7_e) = san.sanitize(a, "<math><mi//xlink:href=\"data:x,<script>alert(1)</script>\">x</mi></math>", san.default_policy())
    if atk7_e != ok { os.exit(187) }
    if str.contains(atk7_o, "<script") { os.exit(188) }
    if str.contains(atk7_o, "data:x") { os.exit(189) }
    let (atk7_o2, atk7_e2) = san.sanitize(a, atk7_o, san.default_policy())
    if atk7_e2 != ok || !str.eq(atk7_o2, atk7_o) { os.exit(190) }
    let (atk8_o, atk8_e) = san.sanitize(a, "<form><math><mtext></form><form><mglyph><style></math><img src onerror=alert(1)>", san.default_policy())
    if atk8_e != ok { os.exit(191) }
    if str.contains(atk8_o, "onerror=") { os.exit(192) }
    if str.contains(atk8_o, "<style") { os.exit(193) }
    let (atk8_o2, atk8_e2) = san.sanitize(a, atk8_o, san.default_policy())
    if atk8_e2 != ok || !str.eq(atk8_o2, atk8_o) { os.exit(194) }
    let (atk9_o, atk9_e) = san.sanitize(a, "<svg><style><img src onerror=alert(1)></style></svg>", san.default_policy())
    if atk9_e != ok { os.exit(195) }
    if str.contains(atk9_o, "onerror=") { os.exit(196) }
    if str.contains(atk9_o, "<style") { os.exit(197) }
    let (atk9_o2, atk9_e2) = san.sanitize(a, atk9_o, san.default_policy())
    if atk9_e2 != ok || !str.eq(atk9_o2, atk9_o) { os.exit(198) }
    let (atk10_o, atk10_e) = san.sanitize(a, "<a href=\"http://ok\" ONCLICK=\"x\" OnMouseOver=\"y\">k</a>", san.default_policy())
    if atk10_e != ok { os.exit(199) }
    if str.contains(atk10_o, "onclick") { os.exit(200) }
    if str.contains(atk10_o, "onmouseover") { os.exit(201) }
    let (atk10_o2, atk10_e2) = san.sanitize(a, atk10_o, san.default_policy())
    if atk10_e2 != ok || !str.eq(atk10_o2, atk10_o) { os.exit(202) }
    let (atk11_o, atk11_e) = san.sanitize(a, "<p title=\"</p><script>alert(1)</script>\">t</p>", san.default_policy())
    if atk11_e != ok { os.exit(203) }
    if str.contains(atk11_o, "<script") { os.exit(204) }
    let (atk11_o2, atk11_e2) = san.sanitize(a, atk11_o, san.default_policy())
    if atk11_e2 != ok || !str.eq(atk11_o2, atk11_o) { os.exit(205) }
    let (atk12_o, atk12_e) = san.sanitize(a, "<div><!--[if IE]><script>alert(1)</script><![endif]--></div>", san.default_policy())
    if atk12_e != ok { os.exit(206) }
    if str.contains(atk12_o, "<script") { os.exit(207) }
    if str.contains(atk12_o, "alert") { os.exit(208) }
    let (atk12_o2, atk12_e2) = san.sanitize(a, atk12_o, san.default_policy())
    if atk12_e2 != ok || !str.eq(atk12_o2, atk12_o) { os.exit(209) }
    let (atk13_o, atk13_e) = san.sanitize(a, "<script>alert(1)</script><SCRIPT SRC=//evil/x.js></SCRIPT><sCrIpT>x</sCrIpT>", san.default_policy())
    if atk13_e != ok { os.exit(210) }
    if str.contains(atk13_o, "script") { os.exit(211) }
    if str.contains(atk13_o, "alert") { os.exit(212) }
    if str.contains(atk13_o, "evil") { os.exit(213) }
    let (atk13_o2, atk13_e2) = san.sanitize(a, atk13_o, san.default_policy())
    if atk13_e2 != ok || !str.eq(atk13_o2, atk13_o) { os.exit(214) }
    let (atk14_o, atk14_e) = san.sanitize(a, "<base href=\"javascript:alert(1)//\"><link rel=stylesheet href=//evil/x.css><meta http-equiv=refresh content=\"0;url=javascript:alert(1)\">", san.default_policy())
    if atk14_e != ok { os.exit(215) }
    if str.contains(atk14_o, "<base") { os.exit(216) }
    if str.contains(atk14_o, "<link") { os.exit(217) }
    if str.contains(atk14_o, "<meta") { os.exit(218) }
    if str.contains(atk14_o, "javascript") { os.exit(219) }
    let (atk14_o2, atk14_e2) = san.sanitize(a, atk14_o, san.default_policy())
    if atk14_e2 != ok || !str.eq(atk14_o2, atk14_o) { os.exit(220) }
    let (x0_o, x0_e) = san.sanitize(a, "<blockquote cite=\"javascript:x\">q</blockquote><q cite=\"http://c/\">q</q><del cite=\"/d\" datetime=\"2020-01-01\">d</del>", san.default_policy())
    if x0_e != ok { os.exit(221) }
    if !str.eq(x0_o, "<blockquote>q</blockquote><q cite=\"http://c/\">q</q><del cite=\"/d\" datetime=\"2020-01-01\">d</del>") { os.exit(222) }
    let (x0_o2, x0_e2) = san.sanitize(a, x0_o, san.default_policy())
    if x0_e2 != ok || !str.eq(x0_o2, x0_o) { os.exit(223) }
    let (note0_o, note0_e) = san.sanitize(a, "<table><tr><td>c</td></tr></table>", san.default_policy())
    if note0_e != ok || str.contains(note0_o, "<script") { os.exit(224) }
    let (note0_o2, note0_e2) = san.sanitize(a, note0_o, san.default_policy())
    if note0_e2 != ok || !str.eq(note0_o2, note0_o) { os.exit(225) }
    let (note1_o, note1_e) = san.sanitize(a, "<b><i>x</b>y</i>", san.default_policy())
    if note1_e != ok || str.contains(note1_o, "<script") { os.exit(226) }
    let (note1_o2, note1_e2) = san.sanitize(a, note1_o, san.default_policy())
    if note1_e2 != ok || !str.eq(note1_o2, note1_o) { os.exit(227) }
    let (nest50_o, nest50_e) = san.sanitize(a, "<div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div>x</div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div>", san.default_policy())
    if nest50_e != ok { os.exit(228) }
    if !str.eq(nest50_o, "<div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div>x</div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div></div>") { os.exit(229) }
    let (nest50_o2, nest50_e2) = san.sanitize(a, nest50_o, san.default_policy())
    if nest50_e2 != ok || !str.eq(nest50_o2, nest50_o) { os.exit(230) }
    let (deep_o, deep_e) = san.sanitize(a, "<div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div>x", san.default_policy())
    if deep_e != san.TooDeep { os.exit(231) }
    var shallow = san.default_policy()
    shallow.max_depth = 10u16
    let (shallow_o, shallow_e) = san.sanitize(a, "<div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div><div>x", shallow)
    if shallow_e != san.TooDeep { os.exit(232) }
    let (bad_o, bad_e) = san.sanitize(a, "<p>\xff\xfe</p>", san.default_policy())
    if bad_e != san.Encoding { os.exit(233) }
    if san.url_allowed("HTTPS://x", san.default_policy()) != true { os.exit(234) }
    if san.url_allowed("javascript:x", san.default_policy()) != false { os.exit(235) }
    if san.url_allowed("java\tscript:x", san.default_policy()) != false { os.exit(236) }
    if san.url_allowed("/a:b", san.default_policy()) != true { os.exit(237) }
    if san.url_allowed("#frag", san.default_policy()) != true { os.exit(238) }
    ret ok
}
