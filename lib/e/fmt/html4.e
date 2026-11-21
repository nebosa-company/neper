// HTML as libxml2's HTML 4 parser reads it (R's xml2::read_html): a recovering parser that builds
// whatever tree its own rules give, never refusing markup -- implied html, head and body (and a
// paragraph around loose text), elements closed by the start tag of the next one through its
// start-close table, end tags ending everything above them up to an end-tag priority barrier,
// unmatched end tags ignored, the HTML 4 entity table, boolean attributes taking their own name,
// script and style bodies kept raw until their end tag, `<br/>` and `<p/>` closed on the spot,
// whitespace-only text dropped where libxml2 judges it ignorable. The tree is an `e.fmt.xml`
// Document (node 0 the document); a second top-level element after `</html>` is a sibling of the
// first, as libxml2 builds it. e.fmt.html is the WHATWG tree builder and builds different trees:
// use this module only for libxml2's. Only an unterminated start tag at the end of the input is
// `Invalid` (xml2 raises there).
//
// ponytail: whitespace is judged over a whole text run (libxml2 judges 1000-byte chunks); input
// is read as UTF-8 bytes without validation; the document type is not a node.
use e.fmt.xml as xml
use e.mem
use e.str

error Invalid

fn closers() -> str { ret "a:a,fieldset,table,td,th;address:dd,dl,dt,form,li,ul;b:center,p,td,th;big:p;caption:col,colgroup,tbody,tfoot,thead,tr;colgroup:colgroup,tbody,tfoot,thead,tr;dd:dt;dir:dd,dl,dt,form,ul;dl:form,li;dt:dd,dl;font:center,td,th;form:form;h1:fieldset,form,li,p,table;h2:fieldset,form,li,p,table;h3:fieldset,form,li,p,table;h4:fieldset,form,li,p,table;h5:fieldset,form,li,p,table;h6:fieldset,form,li,p,table;head:a,abbr,acronym,address,b,bdo,big,blockquote,body,br,center,cite,code,dd,dfn,dir,div,dl,dt,em,fieldset,font,form,frameset,h1,h2,h3,h4,h5,h6,hr,i,iframe,img,kbd,li,map,menu,ol,p,pre,q,s,samp,small,span,strike,strong,sub,sup,table,tt,u,ul,var;i:center,p,td,th;legend:fieldset;li:li;menu:dd,dl,dt,form,ul;ol:form;option:optgroup,option;p:address,blockquote,body,caption,center,col,colgroup,dd,dir,div,dl,dt,fieldset,form,frameset,h1,h2,h3,h4,h5,h6,head,hr,li,menu,ol,p,pre,table,tbody,td,tfoot,th,title,tr,ul;pre:dd,dl,dt,fieldset,form,li,table,ul;s:p;script:noscript;small:p;span:td,th;strike:p;style:body,frameset;tbody:tbody,tfoot;td:tbody,td,tfoot,th,tr;tfoot:tbody;th:tbody,td,tfoot,th,tr;thead:tbody,tfoot;title:body,frameset;tr:tbody,tfoot,tr;tt:p;u:p,td,th;ul:address,form,menu,pre" }
fn entities() -> str { ret "AElig=198;Aacute=193;Acirc=194;Agrave=192;Alpha=913;Aring=197;Atilde=195;Auml=196;Beta=914;Ccedil=199;Chi=935;Dagger=8225;Delta=916;ETH=208;Eacute=201;Ecirc=202;Egrave=200;Epsilon=917;Eta=919;Euml=203;Gamma=915;Iacute=205;Icirc=206;Igrave=204;Iota=921;Iuml=207;Kappa=922;Lambda=923;Mu=924;Ntilde=209;Nu=925;OElig=338;Oacute=211;Ocirc=212;Ograve=210;Omega=937;Omicron=927;Oslash=216;Otilde=213;Ouml=214;Phi=934;Pi=928;Prime=8243;Psi=936;Rho=929;Scaron=352;Sigma=931;THORN=222;Tau=932;Theta=920;Uacute=218;Ucirc=219;Ugrave=217;Upsilon=933;Uuml=220;Xi=926;Yacute=221;Yuml=376;Zeta=918;aacute=225;acirc=226;acute=180;aelig=230;agrave=224;alefsym=8501;alpha=945;amp=38;and=8743;ang=8736;apos=39;aring=229;asymp=8776;atilde=227;auml=228;bdquo=8222;beta=946;brvbar=166;bull=8226;cap=8745;ccedil=231;cedil=184;cent=162;chi=967;circ=710;clubs=9827;cong=8773;copy=169;crarr=8629;cup=8746;curren=164;dArr=8659;dagger=8224;darr=8595;deg=176;delta=948;diams=9830;divide=247;eacute=233;ecirc=234;egrave=232;empty=8709;emsp=8195;ensp=8194;epsilon=949;equiv=8801;eta=951;eth=240;euml=235;euro=8364;exist=8707;fnof=402;forall=8704;frac12=189;frac14=188;frac34=190;frasl=8260;gamma=947;ge=8805;gt=62;hArr=8660;harr=8596;hearts=9829;hellip=8230;iacute=237;icirc=238;iexcl=161;igrave=236;image=8465;infin=8734;int=8747;iota=953;iquest=191;isin=8712;iuml=239;kappa=954;lArr=8656;lambda=955;lang=9001;laquo=171;larr=8592;lceil=8968;ldquo=8220;le=8804;lfloor=8970;lowast=8727;loz=9674;lrm=8206;lsaquo=8249;lsquo=8216;lt=60;macr=175;mdash=8212;micro=181;middot=183;minus=8722;mu=956;nabla=8711;nbsp=160;ndash=8211;ne=8800;ni=8715;not=172;notin=8713;nsub=8836;ntilde=241;nu=957;oacute=243;ocirc=244;oelig=339;ograve=242;oline=8254;omega=969;omicron=959;oplus=8853;or=8744;ordf=170;ordm=186;oslash=248;otilde=245;otimes=8855;ouml=246;para=182;part=8706;permil=8240;perp=8869;phi=966;pi=960;piv=982;plusmn=177;pound=163;prime=8242;prod=8719;prop=8733;psi=968;quot=34;rArr=8658;radic=8730;rang=9002;raquo=187;rarr=8594;rceil=8969;rdquo=8221;real=8476;reg=174;rfloor=8971;rho=961;rlm=8207;rsaquo=8250;rsquo=8217;sbquo=8218;scaron=353;sdot=8901;sect=167;shy=173;sigma=963;sigmaf=962;sim=8764;spades=9824;sub=8834;sube=8838;sum=8721;sup=8835;sup1=185;sup2=178;sup3=179;supe=8839;szlig=223;tau=964;there4=8756;theta=952;thetasym=977;thinsp=8201;thorn=254;tilde=732;times=215;trade=8482;uArr=8657;uacute=250;uarr=8593;ucirc=251;ugrave=249;uml=168;upsih=978;upsilon=965;uuml=252;weierp=8472;xi=958;yacute=253;yen=165;yuml=255;zeta=950;zwj=8205;zwnj=8204" }
fn keep_blanks() -> str { ret ",a,abbr,acronym,address,applet,b,bdo,big,blockquote,body,button,caption,center,cite,code,dd,del,dfn,div,dt,em,font,form,h1,h2,h3,h4,h5,h6,i,iframe,ins,kbd,label,legend,li,noframes,noscript,object,p,pre,q,s,samp,small,span,strike,strong,td,th,tt,u,var," }
fn empty() -> str { ret ",area,base,basefont,br,col,frame,hr,img,input,isindex,link,meta,param," }
fn boolean() -> str { ret ",checked,compact,declare,defer,disabled,ismap,multiple,nohref,noresize,noshade,nowrap,readonly,selected," }

type P = struct {
    a: *mem.Arena,
    src: []const u8,
    at: usize,
    nodes: []xml.Node,
    prev: []u32,
    used: usize,
    tb: []u8,
    tlen: usize,
    tstart: usize,
    text_node: u32,
    ab: []u8,
    alen: usize,
    sc: []u8,
    names: []str,
    ids: []u32,
    depth: usize,
    html: u32,
    skipped: u32,
    ext_id: str,
    attrs: []xml.Attribute,
    nattrs: usize,
    root: u32,
    failed: bool,
}

fn cur(p: *P) -> u8 {
    if p.at < p.src.len { ret p.src[p.at] }
    ret 0u8
}

fn nxt(p: *P, k: usize) -> u8 {
    let i = p.at + k
    if i < p.src.len { ret p.src[i] }
    ret 0u8
}

fn is_blank(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn is_letter(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn skip_blanks(p: *P) {
    while is_blank(cur(p)) { p.at += 1usize }
}

// `item` in a comma-delimited list that starts and ends with a comma.
fn listed(list: str, item: str) -> bool {
    var i = 1usize
    while i < list.len {
        var j = i
        while j < list.len && list[j] != 44u8 { j += 1usize }
        if str.eq(list[i..j], item) { ret true }
        i = j + 1usize
    }
    ret false
}

fn eq_fold(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if lower(x[i]) != lower(y[i]) { ret false }
        i += 1usize
    }
    ret true
}

// Does the start tag `new_tag` end the open element `old_tag`?
fn closes(new_tag: str, old_tag: str) -> bool {
    let tab = closers()
    var i = 0usize
    while i < tab.len {
        var j = i
        while tab[j] != 58u8 { j += 1usize }
        var k = j
        while k < tab.len && tab[k] != 59u8 { k += 1usize }
        if str.eq(tab[i..j], old_tag) {
            var m = j + 1usize
            while m <= k {
                var e = m
                while e < k && tab[e] != 44u8 { e += 1usize }
                if str.eq(tab[m..e], new_tag) { ret true }
                m = e + 1usize
            }
            ret false
        }
        i = k + 1usize
    }
    ret false
}

fn entity_code(name: str) -> u32 {
    let tab = entities()
    var i = 0usize
    while i < tab.len {
        var j = i
        while tab[j] != 61u8 { j += 1usize }
        var k = j
        while k < tab.len && tab[k] != 59u8 { k += 1usize }
        if str.eq(tab[i..j], name) {
            var v = 0u32
            var m = j + 1usize
            while m < k {
                v = v * 10u32 + u32(tab[m] - 48u8)
                m += 1usize
            }
            ret v
        }
        i = k + 1usize
    }
    ret 0u32
}

fn end_priority(name: str) -> u32 {
    if str.eq(name, "div") { ret 150u32 }
    if str.eq(name, "td") || str.eq(name, "th") { ret 160u32 }
    if str.eq(name, "tr") { ret 170u32 }
    if str.eq(name, "thead") { ret 180u32 }
    if str.eq(name, "tbody") { ret 190u32 }
    if str.eq(name, "tfoot") { ret 200u32 }
    if str.eq(name, "table") { ret 220u32 }
    if str.eq(name, "head") { ret 230u32 }
    if str.eq(name, "body") { ret 240u32 }
    if str.eq(name, "html") { ret 250u32 }
    ret 100u32
}

fn is_char(c: u32) -> bool {
    if c == 9u32 || c == 10u32 || c == 13u32 { ret true }
    if c >= 32u32 && c <= 55295u32 { ret true }
    if c >= 57344u32 && c <= 65533u32 { ret true }
    ret c >= 65536u32 && c <= 1114111u32
}

// UTF-8 of `c` into p.sc; the length.
fn encode(p: *P, c: u32) -> usize {
    if c < 128u32 {
        p.sc[0usize] = u8(c)
        ret 1usize
    }
    if c < 2048u32 {
        p.sc[0usize] = u8(192u32 | (c >> 6u32))
        p.sc[1usize] = u8(128u32 | (c & 63u32))
        ret 2usize
    }
    if c < 65536u32 {
        p.sc[0usize] = u8(224u32 | (c >> 12u32))
        p.sc[1usize] = u8(128u32 | ((c >> 6u32) & 63u32))
        p.sc[2usize] = u8(128u32 | (c & 63u32))
        ret 3usize
    }
    p.sc[0usize] = u8(240u32 | (c >> 18u32))
    p.sc[1usize] = u8(128u32 | ((c >> 12u32) & 63u32))
    p.sc[2usize] = u8(128u32 | ((c >> 6u32) & 63u32))
    p.sc[3usize] = u8(128u32 | (c & 63u32))
    ret 4usize
}

// --- Tree.

fn attach(p: *P, kind: xml.NodeKind, name: str, value: str, attributes: []const xml.Attribute) -> u32 {
    var parent = 0u32
    if p.depth > 0usize { parent = p.ids[p.depth - 1usize] }
    if p.used >= p.nodes.len {
        p.failed = true
        ret 0u32
    }
    let last = p.nodes[usize(parent)].last_child
    let id = xml.add_node(p.nodes, &p.used, kind, name, value, attributes, parent)
    p.prev[usize(id)] = last
    if kind == .Element && parent == 0u32 && p.root == xml.NONE { p.root = id }
    ret id
}

// Characters go to the open element's last text node, or a new one; with no open element they are dropped.
fn emit_text(p: *P, bytes: []const u8) {
    if p.depth == 0usize || bytes.len == 0usize { ret }
    if p.tlen + bytes.len > p.tb.len {
        p.failed = true
        ret
    }
    let parent = p.ids[p.depth - 1usize]
    let last = p.nodes[usize(parent)].last_child
    var fresh = true
    if last != xml.NONE && last == p.text_node { fresh = false }
    if fresh { p.tstart = p.tlen }
    mem.copy[u8](p.tb[p.tlen..p.tlen + bytes.len], bytes)
    p.tlen += bytes.len
    let v = p.tb[p.tstart..p.tlen]
    if fresh {
        p.text_node = attach(p, .Text, "", v, zero)
    } else {
        p.nodes[usize(last)].value = v
    }
}

fn top_name(p: *P) -> str {
    if p.depth == 0usize { ret "" }
    ret p.names[p.depth - 1usize]
}

fn push_name(p: *P, name: str, id: u32) {
    if p.depth >= p.names.len {
        p.failed = true
        ret
    }
    p.names[p.depth] = name
    p.ids[p.depth] = id
    p.depth += 1usize
    if p.html < 3u32 && str.eq(name, "head") { p.html = 3u32 }
    if p.html < 10u32 && str.eq(name, "body") { p.html = 10u32 }
}

fn start_element(p: *P, name: str, attributes: []const xml.Attribute) {
    let id = attach(p, .Element, name, "", attributes)
    push_name(p, name, id)
}

fn pop_name(p: *P) {
    if p.depth > 0usize { p.depth -= 1usize }
}

fn auto_close(p: *P, new_tag: str) {
    while p.depth > 0usize && closes(new_tag, top_name(p)) { pop_name(p) }
}

fn check_implied(p: *P, new_tag: str) {
    if str.eq(new_tag, "html") { ret }
    if p.depth == 0usize { start_element(p, "html", zero) }
    if str.eq(new_tag, "body") || str.eq(new_tag, "head") { ret }
    let headish = str.eq(new_tag, "script") || str.eq(new_tag, "style") || str.eq(new_tag, "meta") || str.eq(new_tag, "link") || str.eq(new_tag, "title") || str.eq(new_tag, "base")
    if p.depth <= 1usize && headish {
        if p.html >= 3u32 { ret }
        start_element(p, "head", zero)
        ret
    }
    if !str.eq(new_tag, "noframes") && !str.eq(new_tag, "frame") && !str.eq(new_tag, "frameset") {
        if p.html >= 10u32 { ret }
        var i = 0usize
        while i < p.depth {
            if str.eq(p.names[i], "body") || str.eq(p.names[i], "head") { ret }
            i += 1usize
        }
        start_element(p, "body", zero)
    }
}

// Loose text needs a paragraph when nothing, html or head is open.
fn check_paragraph(p: *P) {
    let tag = top_name(p)
    if p.depth == 0usize || str.eq(tag, "html") || str.eq(tag, "head") {
        auto_close(p, "p")
        check_implied(p, "p")
        start_element(p, "p", zero)
    }
}

fn auto_close_on_close(p: *P, name: str) {
    let priority = end_priority(name)
    var i = p.depth
    var found = false
    while i > 0usize && !found {
        i -= 1usize
        if str.eq(p.names[i], name) {
            found = true
        } else {
            if end_priority(p.names[i]) > priority { ret }
        }
    }
    if !found { ret }
    while p.depth > 0usize && !str.eq(top_name(p), name) { pop_name(p) }
}

// libxml2's judgement of whitespace-only text (areBlanks): `run` is all blanks, `p.at` is after it.
fn are_blanks(p: *P, run: []const u8) -> bool {
    var i = 0usize
    while i < run.len {
        if !is_blank(run[i]) { ret false }
        i += 1usize
    }
    let c = cur(p)
    if c == 0u8 { ret true }
    if c != 60u8 { ret false }
    if p.depth == 0usize { ret true }
    let name = top_name(p)
    if str.eq(name, "html") || str.eq(name, "head") { ret true }
    if str.eq(name, "body") && (eq_fold(p.ext_id, "-//W3C//DTD HTML 4.01//EN") || eq_fold(p.ext_id, "-//W3C//DTD HTML 4//EN")) { ret true }
    let node = p.ids[p.depth - 1usize]
    var last = p.nodes[usize(node)].last_child
    while last != xml.NONE && p.nodes[usize(last)].kind == .Comment { last = p.prev[usize(last)] }
    if last == xml.NONE { ret !listed(keep_blanks(), name) }
    if p.nodes[usize(last)].kind == .Text { ret false }
    ret !listed(keep_blanks(), p.nodes[usize(last)].name)
}

// --- Names, references, text.

// An HTML name lower-cased into the name buffer; empty when none starts here.
fn parse_name_lower(p: *P) -> str {
    let c0 = cur(p)
    if !is_letter(c0) && c0 != 95u8 && c0 != 58u8 && c0 != 46u8 { ret "" }
    let start = p.alen
    while true {
        let c = cur(p)
        if !(is_letter(c) || is_digit(c) || c == 58u8 || c == 45u8 || c == 95u8 || c == 46u8) { break }
        if p.alen >= p.ab.len {
            p.failed = true
            break
        }
        p.ab[p.alen] = lower(c)
        p.alen += 1usize
        p.at += 1usize
    }
    ret p.ab[start..p.alen]
}

// XML-style Name, as written (entity names, PI targets).
fn parse_name(p: *P) -> str {
    let c0 = cur(p)
    if !is_letter(c0) && c0 != 95u8 && c0 != 58u8 && c0 < 128u8 { ret "" }
    let start = p.at
    while true {
        let c = cur(p)
        if !(is_letter(c) || is_digit(c) || c == 58u8 || c == 45u8 || c == 95u8 || c == 46u8 || c >= 128u8) { break }
        p.at += 1usize
    }
    ret p.src[start..p.at]
}

fn hex_value(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret u32(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret u32(c - 55u8) }
    ret 99u32
}

// `&#...;` -> the scalar, 0 for none; the reference is consumed either way.
fn parse_char_ref(p: *P) -> u32 {
    var val = 0u32
    var base = 10u32
    if nxt(p, 2usize) == 120u8 || nxt(p, 2usize) == 88u8 {
        p.at += 3usize
        base = 16u32
    } else {
        p.at += 2usize
    }
    while cur(p) != 59u8 {
        let d = hex_value(cur(p))
        if d >= base { break }
        if val < 1114112u32 { val = val * base + d }
        p.at += 1usize
    }
    if cur(p) == 59u8 { p.at += 1usize }
    if is_char(val) { ret val }
    ret 0u32
}

// `&name;` at `&`: the entity's scalar (0 when unknown or no `;`) and the name read.
fn parse_entity_ref(p: *P) -> (u32, str) {
    p.at += 1usize
    let name = parse_name(p)
    if name.len == 0usize { ret (0u32, "") }
    var code = 0u32
    if cur(p) == 59u8 {
        code = entity_code(name)
        if code != 0u32 { p.at += 1usize }
    }
    ret (code, name)
}

fn ab_push(p: *P, c: u8) {
    if p.alen >= p.ab.len {
        p.failed = true
        ret
    }
    p.ab[p.alen] = c
    p.alen += 1usize
}

fn ab_push_scalar(p: *P, c: u32) {
    let n = encode(p, c)
    var i = 0usize
    while i < n {
        ab_push(p, p.sc[i])
        i += 1usize
    }
}

// An attribute value up to `stop` (0: a blank or `>`), references decoded.
fn parse_attr_text(p: *P, stop: u8) -> str {
    let start = p.alen
    while true {
        let c = cur(p)
        if c == 0u8 || c == stop || p.failed { break }
        if stop == 0u8 && (c == 62u8 || is_blank(c)) { break }
        if c == 38u8 {
            if nxt(p, 1usize) == 35u8 {
                let v = parse_char_ref(p)
                if v != 0u32 { ab_push_scalar(p, v) }
            } else {
                let (code, name) = parse_entity_ref(p)
                if name.len == 0usize {
                    ab_push(p, 38u8)
                } else {
                    if code == 0u32 {
                        ab_push(p, 38u8)
                        var i = 0usize
                        while i < name.len {
                            ab_push(p, name[i])
                            i += 1usize
                        }
                    } else {
                        ab_push_scalar(p, code)
                    }
                }
            }
        } else {
            ab_push(p, c)
            p.at += 1usize
        }
    }
    ret p.ab[start..p.alen]
}

fn skip_to_gt(p: *P) {
    while cur(p) != 0u8 && cur(p) != 62u8 { p.at += 1usize }
}

// --- Markup.

fn parse_comment(p: *P) {
    p.at += 4usize
    var q = cur(p)
    if q == 0u8 {
        ret
    }
    p.at += 1usize
    var r = cur(p)
    if r == 0u8 {
        ret
    }
    p.at += 1usize
    var c = cur(p)
    let start = p.alen
    while c != 0u8 && (c != 62u8 || r != 45u8 || q != 45u8) {
        ab_push(p, q)
        q = r
        r = c
        p.at += 1usize
        c = cur(p)
    }
    if c == 62u8 {
        p.at += 1usize
        let _ = attach(p, .Comment, "", p.ab[start..p.alen], zero)
    }
}

fn parse_pi(p: *P) {
    p.at += 2usize
    let tgt = parse_name(p)
    if tgt.len == 0usize { ret }
    if cur(p) == 62u8 {
        p.at += 1usize
        let _ = attach(p, .Processing, tgt, "", zero)
        ret
    }
    skip_blanks(p)
    let start = p.at
    while cur(p) != 0u8 && cur(p) != 62u8 { p.at += 1usize }
    if cur(p) == 62u8 {
        let data = p.src[start..p.at]
        p.at += 1usize
        let _ = attach(p, .Processing, tgt, data, zero)
    }
}

fn parse_doctype(p: *P) {
    p.at += 9usize
    skip_blanks(p)
    let _ = parse_name(p)
    skip_blanks(p)
    if nxt(p, 0usize) == 80u8 || nxt(p, 0usize) == 112u8 {
        // PUBLIC "id" ...
        p.at += 6usize
        skip_blanks(p)
        let q = cur(p)
        if q == 34u8 || q == 39u8 {
            p.at += 1usize
            let start = p.at
            while cur(p) != 0u8 && cur(p) != q { p.at += 1usize }
            p.ext_id = p.src[start..p.at]
        }
    }
    skip_to_gt(p)
    if cur(p) == 62u8 { p.at += 1usize }
}

fn is_doctype(p: *P) -> bool {
    if cur(p) != 60u8 || nxt(p, 1usize) != 33u8 { ret false }
    let w = "DOCTYPE"
    var i = 0usize
    while i < 7usize {
        if lower(nxt(p, 2usize + i)) != lower(w[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn parse_char_data(p: *P) {
    let start = p.at
    var dirty = false
    while true {
        let c = cur(p)
        if c == 0u8 || c == 60u8 || c == 38u8 { break }
        if c < 32u8 && c != 9u8 && c != 10u8 && c != 13u8 { dirty = true }
        p.at += 1usize
    }
    var run = p.src[start..p.at]
    if dirty {
        // Control characters are not XML characters: dropped.
        let from = p.alen
        var i = 0usize
        while i < run.len {
            if run[i] >= 32u8 || run[i] == 9u8 || run[i] == 10u8 || run[i] == 13u8 { ab_push(p, run[i]) }
            i += 1usize
        }
        run = p.ab[from..p.alen]
    }
    if run.len == 0usize { ret }
    if are_blanks(p, run) { ret }
    check_paragraph(p)
    emit_text(p, run)
}

fn parse_reference(p: *P) {
    if nxt(p, 1usize) == 35u8 {
        let v = parse_char_ref(p)
        if v == 0u32 { ret }
        let n = encode(p, v)
        check_paragraph(p)
        emit_text(p, p.sc[0usize..n])
        ret
    }
    let (code, name) = parse_entity_ref(p)
    if name.len == 0usize {
        check_paragraph(p)
        emit_text(p, "&")
        ret
    }
    if code == 0u32 {
        check_paragraph(p)
        emit_text(p, "&")
        emit_text(p, name)
        ret
    }
    let n = encode(p, code)
    check_paragraph(p)
    emit_text(p, p.sc[0usize..n])
}

// Script and style bodies: raw until the end tag of the open element, as one node.
fn parse_script(p: *P) {
    let name = top_name(p)
    let start = p.at
    while true {
        let c = cur(p)
        if c == 0u8 { break }
        if c == 60u8 && nxt(p, 1usize) == 47u8 {
            var same = true
            var i = 0usize
            while i < name.len {
                if lower(nxt(p, 2usize + i)) != name[i] { same = false }
                i += 1usize
            }
            if same { break }
        }
        p.at += 1usize
    }
    if p.at > start && p.depth > 0usize {
        if p.tlen + (p.at - start) > p.tb.len {
            p.failed = true
            ret
        }
        let from = p.tlen
        var i = start
        while i < p.at {
            let c = p.src[i]
            if c >= 32u8 || c == 9u8 || c == 10u8 || c == 13u8 {
                p.tb[p.tlen] = c
                p.tlen += 1usize
            }
            i += 1usize
        }
        let _ = attach(p, .Text, "", p.tb[from..p.tlen], zero)
        p.text_node = xml.NONE
    }
}

fn parse_end_tag(p: *P) {
    p.at += 2usize
    let name = parse_name_lower(p)
    if name.len == 0usize { ret }
    skip_blanks(p)
    skip_to_gt(p)
    if cur(p) == 62u8 { p.at += 1usize }
    if p.skipped > 0u32 && (str.eq(name, "html") || str.eq(name, "body") || str.eq(name, "head")) {
        p.skipped -= 1u32
        ret
    }
    var i = p.depth
    var found = false
    while i > 0usize && !found {
        i -= 1usize
        if str.eq(p.names[i], name) { found = true }
    }
    if !found { ret }
    auto_close_on_close(p, name)
    if str.eq(top_name(p), name) { pop_name(p) }
}

// One attribute at the cursor; false when no name starts here.
fn parse_attribute(p: *P) -> bool {
    let name = parse_name_lower(p)
    if name.len == 0usize { ret false }
    skip_blanks(p)
    var value = ""
    var given = false
    if cur(p) == 61u8 {
        p.at += 1usize
        skip_blanks(p)
        given = true
        let q = cur(p)
        if q == 34u8 || q == 39u8 {
            p.at += 1usize
            value = parse_attr_text(p, q)
            if cur(p) == q { p.at += 1usize }
        } else {
            value = parse_attr_text(p, 0u8)
        }
    }
    if !given && listed(boolean(), name) { value = name }
    var i = 0usize
    while i < p.nattrs {
        if str.eq(p.attrs[i].name, name) { ret true }
        i += 1usize
    }
    if p.nattrs < p.attrs.len {
        p.attrs[p.nattrs] = xml.Attribute { name: name, value: value }
        p.nattrs += 1usize
    }
    ret true
}

// The start tag at `<`: -1 nothing opened, 0 opened, 1 discarded (a misplaced html, head or body).
fn parse_start_tag(p: *P) -> i32 {
    p.at += 1usize
    let name = parse_name_lower(p)
    if name.len == 0usize {
        skip_to_gt(p)
        ret -1
    }
    auto_close(p, name)
    check_implied(p, name)
    var discard = false
    if p.depth > 0usize && str.eq(name, "html") { discard = true }
    if p.depth != 1usize && str.eq(name, "head") { discard = true }
    if str.eq(name, "body") {
        var i = 0usize
        while i < p.depth {
            if str.eq(p.names[i], "body") { discard = true }
            i += 1usize
        }
    }
    if discard { p.skipped += 1u32 }
    p.nattrs = 0usize
    skip_blanks(p)
    while cur(p) != 0u8 && cur(p) != 62u8 && (cur(p) != 47u8 || nxt(p, 1usize) != 62u8) && !p.failed {
        if !parse_attribute(p) {
            while cur(p) != 0u8 && !is_blank(cur(p)) && cur(p) != 62u8 && (cur(p) != 47u8 || nxt(p, 1usize) != 62u8) { p.at += 1usize }
        }
        skip_blanks(p)
    }
    if !discard {
        var list: []xml.Attribute = zero
        if p.nattrs > 0usize {
            let (made, made_error) = mem.alloc[xml.Attribute](p.a, p.nattrs)
            if made_error != ok {
                p.failed = true
                ret -1
            }
            mem.copy[xml.Attribute](made, p.attrs[0usize..p.nattrs])
            list = made
        }
        start_element(p, name, list)
        ret 0
    }
    ret 1
}

fn parse_element(p: *P) -> bool {
    let failed = parse_start_tag(p)
    let name = top_name(p)
    if failed == -1 || p.depth == 0usize {
        if cur(p) == 62u8 { p.at += 1usize }
        ret true
    }
    if cur(p) == 47u8 && nxt(p, 1usize) == 62u8 {
        p.at += 2usize
        pop_name(p)
        ret true
    }
    if cur(p) == 62u8 {
        p.at += 1usize
    } else {
        // The end of the input inside the tag: xml2 raises.
        if cur(p) == 0u8 { ret false }
        pop_name(p)
        ret true
    }
    if listed(empty(), name) { pop_name(p) }
    ret true
}

fn parse_content(p: *P) -> bool {
    while !p.failed {
        let c = cur(p)
        if c == 0u8 { break }
        if c == 60u8 && nxt(p, 1usize) == 47u8 {
            parse_end_tag(p)
            continue
        }
        if c == 60u8 && is_letter(nxt(p, 1usize)) {
            // The name is read ahead: a start tag that closes the open element does so first.
            let mark = p.at
            let save = p.alen
            p.at += 1usize
            let name = parse_name_lower(p)
            p.at = mark
            p.alen = save
            if p.depth > 0usize && closes(name, top_name(p)) {
                auto_close(p, name)
                continue
            }
        }
        let top = top_name(p)
        if str.eq(top, "script") || str.eq(top, "style") {
            parse_script(p)
            continue
        }
        if c == 60u8 && nxt(p, 1usize) == 33u8 {
            if is_doctype(p) {
                parse_doctype(p)
            } else {
                if nxt(p, 2usize) == 45u8 && nxt(p, 3usize) == 45u8 {
                    parse_comment(p)
                } else {
                    p.at += 2usize
                    skip_to_gt(p)
                    if cur(p) == 62u8 { p.at += 1usize }
                }
            }
            continue
        }
        if c == 60u8 && nxt(p, 1usize) == 63u8 {
            parse_pi(p)
            continue
        }
        if c == 60u8 && is_letter(nxt(p, 1usize)) {
            if !parse_element(p) { ret false }
            continue
        }
        if c == 60u8 {
            emit_text(p, "<")
            p.at += 1usize
            continue
        }
        if c == 38u8 {
            parse_reference(p)
        } else {
            parse_char_data(p)
        }
    }
    ret true
}

// The document as libxml2's HTML parser builds it; `Invalid` for an empty document or an
// unterminated start tag at the end of the input.
fn parse(a: *mem.Arena, source: []const u8) -> (xml.Document, err) {
    let cap = source.len * 4usize + 16usize
    let (nodes, nodes_error) = mem.alloc[xml.Node](a, cap)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (prev, prev_error) = mem.alloc[u32](a, cap)
    if prev_error != ok { ret (zero, prev_error) }
    let (names, names_error) = mem.alloc[str](a, cap)
    if names_error != ok { ret (zero, names_error) }
    let (ids, ids_error) = mem.alloc[u32](a, cap)
    if ids_error != ok { ret (zero, ids_error) }
    let (tb, tb_error) = mem.alloc[u8](a, source.len * 2usize + 64usize)
    if tb_error != ok { ret (zero, tb_error) }
    let (ab, ab_error) = mem.alloc[u8](a, source.len * 2usize + 64usize)
    if ab_error != ok { ret (zero, ab_error) }
    let (sc, sc_error) = mem.alloc[u8](a, 8usize)
    if sc_error != ok { ret (zero, sc_error) }
    let (attrs, attrs_error) = mem.alloc[xml.Attribute](a, 1024usize)
    if attrs_error != ok { ret (zero, attrs_error) }
    var p = P { src: source, at: 0usize, nodes: nodes, prev: prev, used: 0usize, tb: tb, tlen: 0usize, tstart: 0usize, text_node: xml.NONE, ab: ab, alen: 0usize, sc: sc, names: names, ids: ids, depth: 0usize, html: 0u32, skipped: 0u32, ext_id: "", attrs: attrs, nattrs: 0usize, root: xml.NONE, failed: false, a: a }
    let _ = xml.add_node(p.nodes, &p.used, .Document, "", "", zero, xml.NONE)
    skip_blanks(&p)
    if cur(&p) == 0u8 { ret (zero, Invalid) }
    while (cur(&p) == 60u8 && nxt(&p, 1usize) == 33u8 && nxt(&p, 2usize) == 45u8 && nxt(&p, 3usize) == 45u8) || (cur(&p) == 60u8 && nxt(&p, 1usize) == 63u8) {
        if nxt(&p, 1usize) == 63u8 { parse_pi(&p) } else { parse_comment(&p) }
        skip_blanks(&p)
    }
    if is_doctype(&p) { parse_doctype(&p) }
    skip_blanks(&p)
    while (cur(&p) == 60u8 && nxt(&p, 1usize) == 33u8 && nxt(&p, 2usize) == 45u8 && nxt(&p, 3usize) == 45u8) || (cur(&p) == 60u8 && nxt(&p, 1usize) == 63u8) {
        if nxt(&p, 1usize) == 63u8 { parse_pi(&p) } else { parse_comment(&p) }
        skip_blanks(&p)
    }
    if !parse_content(&p) { ret (zero, Invalid) }
    if p.failed { ret (zero, Invalid) }
    if p.root == xml.NONE { ret (zero, Invalid) }
    ret (xml.Document { nodes: p.nodes[..p.used], root: p.root }, ok)
}
