// The planned names the e.text modules were missing, in one fixture: regex automata
// (Thompson NFA, Pike VM, subset DFA, Moore minimization, DFA runs) against Python's
// `re` and a replica of the construction; Aho-Corasick under its bare name; the
// collation `compare`; charset detection; Elias-Fano postings with get and next-geq;
// ellipsis truncation over synthetic fonts; the ROUGE suite; font fallback and runs;
// the Snowball English stemmer against snowballstemmer 3.1.1 on 200 words; BPE under
// its bare name against a replica; UAX #31 identifiers against `str.isidentifier`;
// and the UTF-16 codec. Expectations come from scratch/text_gaps/{regex_ref,ref}.py.

use e.io
use e.mem
use e.os
use e.text.collate
use e.text.encoding
use e.text.index
use e.text.layout
use e.text.metric
use e.text.regex
use e.text.search
use e.text.shape
use e.text.stem
use e.text.tokenize
use e.text.unicode
use e.text.utf8

fn same(a: str, b: str) -> bool {
    ret mem.eq[u8](a, b)
}

// The `index`-th field of `s` split at `sep`.
fn nth(s: str, which: usize, sep: u8) -> str {
    var start = 0usize
    var i = 0usize
    var k = 0usize
    while i < s.len && k < which {
        if s[i] == sep {
            k += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if k < which { ret s[s.len..] }
    var end = start
    while end < s.len && s[end] != sep { end += 1usize }
    ret s[start..end]
}

fn number(s: str) -> usize {
    var v = 0usize
    var i = 0usize
    while i < s.len {
        v = v * 10usize + usize(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

// "start,end" or "x" for no match.
fn pair(s: str) -> (usize, usize, bool) {
    if same(s, "x") { ret (0usize, 0usize, false) }
    ret (number(nth(s, 0usize, 44u8)), number(nth(s, 1usize, 44u8)), true)
}

fn near(x: f64, y: f64) -> bool {
    let d = x - y
    ret d < 0.000000001f64 && d > -0.000000001f64
}

fn guess_is(src: str, want: encoding.Encoding, confidence: u8) -> bool {
    let g = encoding.detect(src)
    ret g.encoding == want && g.confidence == confidence
}

fn rouge_is(r: metric.Rouge, p: f64, rc: f64, f: f64) -> bool {
    ret near(r.precision, p) && near(r.recall, rc) && near(r.f1, f)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1-8: regex automata over 12 patterns x 8 inputs.
    let pats: [12]str = [12]str{ "abc", "a(b|c)*d", "[a-c]+x?", "\\d{2,4}", "(ab|a)(bc|c)?", "^a.*b$", "colou?r", "x*", "(a|b)*abb", "[^0-9 ]+", "(\\w+)@(\\w+)\\.com", "a{3}|b{2,}" }
    let ins: [12]str = [12]str{ "abc;ab;abcd;xabc;;abcabc;aabc;abd", "ad;abcbd;abbd;abc;d;acd;abcbdx;xad", "a;abcx;x;cccx;abcxx;d;bax;axb", "12;1;1234;12345;a12;9999;123a;", "abc;a;ab;ac;abcc;b;abbc;aab", "ab;axxb;a;b;aab;xab;abx;abab", "color;colour;colouur;colr;xcolorx;COLOR;col;colours", ";x;xxx;y;xy;yx;xxxy;a", "abb;aabb;babb;ab;abba;bbabb;abbabb;", "abc;a1;;hello;a b;!!;1;x", "joe@mail.com;a@b.com;@b.com;joe@mail.org;x joe@m.com y;a@b.comm;a@.com;a_b@c9.com", "aaa;aa;bb;bbbb;aaaa;b;ab;aaab" }
    let full: [12]str = [12]str{ "10000000", "11100100", "11010010", "10100100", "11110010", "11001001", "11000000", "11100000", "11100110", "10010101", "11000001", "10110000" }
    let srch: [12]str = [12]str{ "0,3;x;0,3;1,4;x;0,3;1,4;x", "0,2;0,5;0,4;x;x;0,3;0,5;1,3", "0,1;0,4;x;0,4;0,4;x;0,3;0,2", "0,2;x;0,4;0,4;1,3;0,4;0,3;x", "0,3;0,1;0,2;0,2;0,3;x;0,4;0,1", "0,2;0,4;x;x;0,3;x;x;0,4", "0,5;0,6;x;x;1,6;x;x;0,6", "0,0;0,1;0,3;0,0;0,1;0,0;0,3;0,0", "0,3;0,4;0,4;x;0,3;0,5;0,6;x", "0,3;0,1;x;0,5;0,1;0,2;x;0,1", "0,12;0,7;x;x;2,11;0,7;x;0,10", "0,3;x;0,2;0,4;0,3;x;x;0,3" }
    let counts: [12]u32 = [12]u32{ 5u32, 4u32, 4u32, 6u32, 6u32, 4u32, 8u32, 2u32, 5u32, 3u32, 9u32, 7u32 }
    var p = 0usize
    while p < 12usize {
        let (nfa, nfa_error) = regex.nfa_compile(a, pats[p], zero)
        if nfa_error != ok || regex.nfa_size(nfa) == 0usize { os.exit(1i32) }
        let (dfa, dfa_error) = regex.dfa_from_nfa(a, nfa, 256usize)
        if dfa_error != ok { os.exit(2i32) }
        let (small, small_error) = regex.dfa_minimize(a, dfa)
        if small_error != ok || small.states != usize(counts[p]) || small.states > dfa.states { os.exit(3i32) }
        let flags = full[p]
        var k = 0usize
        while k < 8usize {
            let text = nth(ins[p], k, 59u8)
            let want_full = flags[k] == 49u8
            if regex.dfa_run(dfa, text) != want_full || regex.dfa_run(small, text) != want_full { os.exit(4i32) }
            let (ws, we, has) = pair(nth(srch[p], k, 59u8))
            var caps: [3]regex.Match = zero
            let matched = regex.pike_vm(nfa, text, 0usize, caps[0..])
            if matched != has || (has && (caps[0].start != ws || caps[0].end != we)) { os.exit(5i32) }
            k += 1usize
        }
        p += 1usize
    }
    let (mail, mail_error) = regex.nfa_compile(a, pats[10], zero)
    var groups: [3]regex.Match = zero
    if mail_error != ok || !regex.pike_vm(mail, "joe@mail.com", 0usize, groups[0..]) { os.exit(6i32) }
    if groups[1].start != 0usize || groups[1].end != 3usize || groups[2].start != 4usize || groups[2].end != 8usize { os.exit(6i32) }
    let (big, big_error) = regex.nfa_compile(a, "(a|b)*a(a|b){6}", zero)
    if big_error != ok { os.exit(7i32) }
    let (_, big_dfa_error) = regex.dfa_from_nfa(a, big, 64usize)
    let (wordy, wordy_error) = regex.nfa_compile(a, "\\bfoo", zero)
    if wordy_error != ok { os.exit(7i32) }
    let (_, wordy_dfa_error) = regex.dfa_from_nfa(a, wordy, 64usize)
    if big_dfa_error != regex.TooLarge || wordy_dfa_error != regex.Unsupported { os.exit(7i32) }
    let (plus, plus_error) = regex.nfa_compile(a, "a+", zero)
    if plus_error != ok { os.exit(8i32) }
    let (plus_dfa, plus_dfa_error) = regex.dfa_from_nfa(a, plus, 64usize)
    if plus_dfa_error != ok { os.exit(8i32) }
    let (longest, has_longest) = regex.dfa_longest(plus_dfa, "aaab")
    let (none_at, has_none) = regex.dfa_longest(plus_dfa, "baa")
    if !has_longest || longest != 3usize || has_none || none_at != 0usize { os.exit(8i32) }

    // 9: Aho-Corasick under the plan's name, counting overlapping hits.
    let needles: [4]str = [4]str{ "he", "she", "his", "hers" }
    let (ac, ac_error) = search.aho_corasick(a, needles[0..])
    if ac_error != ok || search.aho_corasick_count(&ac, "ushers he his hers she") != 9usize { os.exit(9i32) }

    // 10: collation compare, numeric and case-folded with a code-point tie-break.
    let opts = collate.Options { case_sensitive: false, numeric: true }
    if collate.compare("file10", "file9", opts) <= 0i32 || collate.compare("File2", "file2", opts) >= 0i32 { os.exit(10i32) }
    if collate.compare("abc", "abd", opts) >= 0i32 || collate.compare("x", "x", opts) != 0i32 { os.exit(10i32) }

    // 11-12: charset detection.
    if !guess_is("\xef\xbb\xbfhello", .Utf8, 100u8) || !guess_is("\xff\xfeh\x00i\x00", .Utf16Le, 100u8) { os.exit(11i32) }
    if !guess_is("\x00h\x00e\x00l\x00l\x00o\x00 \x00w\x00o\x00r\x00l\x00d", .Utf16Be, 70u8) || !guess_is("h\x00e\x00l\x00l\x00o\x00 \x00w\x00o\x00r\x00l\x00d\x00", .Utf16Le, 70u8) { os.exit(11i32) }
    if !guess_is("h\x00\x00\x00e\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00", .Utf32Le, 80u8) || !guess_is("plain ascii text", .Utf8, 60u8) { os.exit(12i32) }
    if !guess_is("h\xc3\xa9llo w\xc3\xb6rld \xe2\x82\xac", .Utf8, 90u8) || !guess_is("h\xe9llo w\xf6rld", .Utf8, 0u8) { os.exit(12i32) }

    // 13-15: Elias-Fano postings.
    let id_text = "307;381;395;406;475;484;506;572;593;704;743;771;964;1014;1090;1181;1235;1758;1811;1828;1971;2372;2652;2995;3234;3249;3425;3433;3477;3552;4156;4389;4429;4514;4560;4632;4727;4774;4775;4796"
    var ids: [40]u32 = zero
    var i = 0usize
    while i < 40usize {
        ids[i] = u32(number(nth(id_text, i, 59u8)))
        i += 1usize
    }
    var ef_bytes: [64]u8 = zero
    let (ef, ef_error) = index.postings_elias_fano(ids[0..], ef_bytes[0..])
    if ef_error != ok || ef.bytes.len != 45usize || ef.l != 6u32 || ef.bytes.len * 8usize > 40usize * 9usize { os.exit(13i32) }
    i = 0usize
    while i < 40usize {
        let (v, v_error) = index.ef_get(ef, i)
        if v_error != ok || v != ids[i] { os.exit(14i32) }
        i += 1usize
    }
    let (_, past_error) = index.ef_get(ef, 40usize)
    if past_error != index.Invalid { os.exit(14i32) }
    let queries: [7]u32 = [7]u32{ 0u32, 307u32, 485u32, 1971u32, 2500u32, 4796u32, 4797u32 }
    let answers: [7]u32 = [7]u32{ 307u32, 307u32, 506u32, 1971u32, 2652u32, 4796u32, 0u32 }
    let positions: [7]usize = [7]usize{ 0usize, 0usize, 6usize, 20usize, 22usize, 39usize, 40usize }
    i = 0usize
    while i < 7usize {
        let (v, at_index, has) = index.ef_next_geq(ef, queries[i])
        if has != (i < 6usize) || at_index != positions[i] || (has && v != answers[i]) { os.exit(15i32) }
        i += 1usize
    }

    // 16-17: ellipsis over a synthetic font (a b c 5.0, space 2.5, ellipsis 10.0 at size 10).
    let latin_data = "\x00\x01\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00head\x00\x00\x00\x00\x00\x00\x00\\\x00\x00\x008hhea\x00\x00\x00\x00\x00\x00\x00\x94\x00\x00\x00$hmtx\x00\x00\x00\x00\x00\x00\x00\xb8\x00\x00\x00 maxp\x00\x00\x00\x00\x00\x00\x00\xd8\x00\x00\x00\x08cmap\x00\x00\x00\x00\x00\x00\x00\xe0\x00\x00\x00\\\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\xe8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x03 \xff8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\x01\xf4\x00\x00\x00\xfa\x00\x00\x01,\x00\x00\x00\xfa\x00\x00\x01\xf4\x00\x00\x01\xf4\x00\x00\x01\xf4\x00\x00\x03\xe8\x00\x00\x00\x00P\x00\x00\x08\x00\x00\x00\x00\x00\x01\x00\x03\x00\x01\x00\x00\x00\x0c\x00\x04\x00P\x00\x00\x00\x10\x00\x00\x00\x00\x00\x00\x00 \x00-\x00.\x00a\x00b\x00c &\xff\xff\x00\x00\x00 \x00-\x00.\x00a\x00b\x00c &\xff\xff\xff\xe1\xff\xd5\xff\xd5\xff\xa3\xff\xa3\xff\xa3\xdf\xe1\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    let hebrew_data = "\x00\x01\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00head\x00\x00\x00\x00\x00\x00\x00\\\x00\x00\x008hhea\x00\x00\x00\x00\x00\x00\x00\x94\x00\x00\x00$hmtx\x00\x00\x00\x00\x00\x00\x00\xb8\x00\x00\x00\x10maxp\x00\x00\x00\x00\x00\x00\x00\xc8\x00\x00\x00\x08cmap\x00\x00\x00\x00\x00\x00\x00\xd0\x00\x00\x00<\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\xe8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04\x01\xf4\x00\x00\x01\x90\x00\x00\x02X\x00\x00\x02X\x00\x00\x00\x00P\x00\x00\x04\x00\x00\x00\x00\x00\x01\x00\x03\x00\x01\x00\x00\x00\x0c\x00\x04\x000\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00x\x05\xd0\x05\xd1\xff\xff\x00\x00\x00x\x05\xd0\x05\xd1\xff\xff\xff\x89\xfa2\xfa2\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00"
    let latin = shape.Font { id: 1u32, data: latin_data, face_index: 0u32 }
    let hebrew = shape.Font { id: 2u32, data: hebrew_data, face_index: 0u32 }
    if shape.validate_font(latin) != ok || shape.validate_font(hebrew) != ok { os.exit(16i32) }
    let choices: [1]layout.FontChoice = [1]layout.FontChoice{ layout.FontChoice { font: latin, size: 10.0 } }
    let style = layout.Style { fonts: choices[0..], language: "", line_height: 0.0 }
    var cut: [32]u8 = zero
    let (e1, e1_error) = layout.ellipsis(a, style, "abc abc abc", 30.0, .End, cut[0..])
    if e1_error != ok || !same(e1, "abc \xe2\x80\xa6") { os.exit(16i32) }
    let (e2, e2_error) = layout.ellipsis(a, style, "abc abc abc", 30.0, .Start, cut[0..])
    if e2_error != ok || !same(e2, "\xe2\x80\xa6 abc") { os.exit(16i32) }
    let (e3, e3_error) = layout.ellipsis(a, style, "abc abc abc", 30.0, .Middle, cut[0..])
    if e3_error != ok || !same(e3, "ab\xe2\x80\xa6bc") { os.exit(17i32) }
    let (e4, e4_error) = layout.ellipsis(a, style, "abc abc abc", 60.0, .End, cut[0..])
    if e4_error != ok || !same(e4, "abc abc abc") { os.exit(17i32) }
    let (e5, e5_error) = layout.ellipsis(a, style, "abc abc abc", 5.0, .End, cut[0..])
    if e5_error != ok || e5.len != 0usize { os.exit(17i32) }
    let (_, e6_error) = layout.ellipsis(a, style, "abc", 5.0, .End, cut[0..2usize])
    if e6_error != layout.TooSmall { os.exit(17i32) }

    // 18: ROUGE-1, ROUGE-2 and ROUGE-L in one call.
    var scratch: [64]usize = zero
    let (rs, rs_error) = metric.rouge("the cat sat on the mat today", "the cat is on the mat", scratch[0..])
    if rs_error != ok || !rouge_is(rs.one, 0.7142857142857143f64, 0.8333333333333334f64, 0.7692307692307692f64) { os.exit(18i32) }
    if !rouge_is(rs.two, 0.5f64, 0.6f64, 0.5454545454545454f64) || !rouge_is(rs.l, 0.7142857142857143f64, 0.8333333333333334f64, 0.7692307692307692f64) { os.exit(18i32) }

    // 19-20: font fallback and runs.
    let fonts: [2]shape.Font = [2]shape.Font{ latin, hebrew }
    if shape.fallback_font(fonts[0..], 97u32) != 0usize || shape.fallback_font(fonts[0..], 120u32) != 1usize || shape.fallback_font(fonts[0..], 1488u32) != 1usize { os.exit(19i32) }
    if shape.fallback_font(fonts[0..], 122u32) != 1usize || shape.fallback_font(fonts[0..0usize], 97u32) != 18446744073709551615usize { os.exit(19i32) }
    var runs: [8]shape.FontRun = zero
    let (run_count, runs_error) = shape.fallback_runs(fonts[0..], "ab x\xd7\x90 c", runs[0..])
    if runs_error != ok || run_count != 3usize || runs[0].font != 0usize || runs[0].end != 3usize { os.exit(20i32) }
    if runs[1].font != 1usize || runs[1].start != 3usize || runs[1].end != 6usize || runs[2].font != 0usize || runs[2].start != 6usize || runs[2].end != 8usize { os.exit(20i32) }

    // 21: the Snowball stemmer on 200 words against snowballstemmer 3.1.1.
    let words = "namespaces raphson wheel number name phonetic requiring differential detachment placement operating sentences sampling yes deutsch case mud grover's contains capabilities progressive summarization sgd auditory reusing links nat smaller truncation saturate skinning cron sdf aggregations preorder bins bfd ask diffing exhibiting rigid applications waypoints notifying http module response discover polyphase espresso shortening glyphs pde acid special bwa network smoothed frozen louvain quantifiers bulk teacher feedback held vae epaxos plane genetic append boltzmann rdma vigen chroma locality christofides get learned blacklist algo structural aborting ebpf duplicates barnes ocr knights tempo literal massive bottom reassembly sensor distance weave stateless folding incorporating calculation hashing iir aging luminance code condition extending taxonomic cgnat adoption bfq ntt zstd ownership delay stratified rankings dial multimodal physics digests transparent voice composite masking signature lazy cluster lineage materialize earliest abbadi results guarantee allow dutertre dfas limiting roadmap sickness regularity certificates augmented converging earth momentum fills adjacent vxlan rumors hyphenated goodness leakage boundaries box canonical dtb renew shapes expectation agreement rmq karger kernel screen nats comparable requirements outer reflect configuration dying skies hopping adding agreed generously communication pasted evening yearly cry sky news early proceed exceeding canning hopped ugly arsenic universities organizations interesting lately emerging ties gaps kiwis this gas"
    let stems = "namespac raphson wheel number name phonet requir differenti detach placement oper sentenc sampl yes deutsch case mud grover contain capabl progress summar sgd auditori reus link nat smaller truncat satur skin cron sdf aggreg preorder bin bfd ask dif exhibit rigid applic waypoint notifi http modul respons discov polyphas espresso shorten glyph pde acid special bwa network smooth frozen louvain quantifi bulk teacher feedback held vae epaxo plane genet append boltzmann rdma vigen chroma local christofid get learn blacklist algo structur abort ebpf duplic barn ocr knight tempo liter massiv bottom reassembl sensor distanc weav stateless fold incorpor calcul hash iir age lumin code condit extend taxonom cgnat adopt bfq ntt zstd ownership delay stratifi rank dial multimod physic digest transpar voic composit mask signatur lazi cluster lineag materi earliest abbadi result guarante allow dutertr dfas limit roadmap sick regular certif augment converg earth momentum fill adjac vxlan rumor hyphen good leakag boundari box canon dtb renew shape expect agreement rmq karger kernel screen nat compar requir outer reflect configur die sky hop add agre generous communic paste evening year cri sky news earli proceed exceed canning hop ugli arsenic universiti organiz interest late emerg tie gap kiwi this gas"
    var buffer: [32]u8 = zero
    i = 0usize
    while i < 200usize {
        let (got, got_error) = stem.snowball(nth(words, i, 32u8), buffer[0..])
        if got_error != ok || !same(got, nth(stems, i, 32u8)) { os.exit(21i32) }
        i += 1usize
    }

    // 22-23: BPE under the plan's name, with an end-of-word marker by convention.
    let corpus_text = "low_ low_ low_ low_ low_ lower_ lower_ newest_ newest_ newest_ newest_ newest_ newest_ widest_ widest_ widest_"
    var corpus: [16]str = zero
    i = 0usize
    while i < 16usize {
        corpus[i] = nth(corpus_text, i, 32u8)
        i += 1usize
    }
    let (b, b_error) = tokenize.bpe_train(a, corpus[0..], 6usize)
    if b_error != ok || b.count != 6usize { os.exit(22i32) }
    let lefts = "e es est l lo n"
    let rights = "s t _ o w e"
    i = 0usize
    while i < 6usize {
        if !same(b.left[i], nth(lefts, i, 32u8)) || !same(b.right[i], nth(rights, i, 32u8)) { os.exit(22i32) }
        i += 1usize
    }
    var pieces: [8]str = zero
    let (t1, t1_error) = tokenize.bpe(&b, "lowest_", pieces[0..], scratch[0..])
    if t1_error != ok || t1 != 2usize || !same(pieces[0], "low") || !same(pieces[1], "est_") { os.exit(23i32) }
    let (t2, t2_error) = tokenize.bpe(&b, "newer_", pieces[0..], scratch[0..])
    if t2_error != ok || t2 != 5usize || !same(pieces[0], "ne") || !same(pieces[4], "_") { os.exit(23i32) }
    let (t3, t3_error) = tokenize.bpe(&b, "widest_", pieces[0..], scratch[0..])
    if t3_error != ok || t3 != 4usize || !same(pieces[3], "est_") { os.exit(23i32) }

    // 24: UAX #31 identifiers against str.isidentifier (category-vs-XID divergences skipped).
    let idents = "hello|_x1|1abc||a b|\xce\xba\xce\xb1\xce\xbb\xcf\x8c\xcf\x82|\xe5\x8f\x98\xe9\x87\x8f|x-y|__init__|a\xcc\x81b|ab\xe2\x80\x8d|\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e|\xc3\xbcn\xc3\xafcode|x2y3|$var|a.b|\xe2\x85\xa7|\xd9\xa0abc|abc\xd9\xa0|a_|\xcf\x80|\xce\xa91|\xd1\x82\xd0\xb5\xd1\x81\xd1\x82|a\xcc\x81|\xcc\x81a|ok?|\xce\xbbx|snake_case|CamelCase|9|_|ab cd|x\xe3\x80\x80|\xc2\xaa"
    let verdicts = "1100011011011100101111110011101001"
    i = 0usize
    while i < 34usize {
        if unicode.is_identifier(nth(idents, i, 124u8)) != (verdicts[i] == 49u8) { os.exit(24i32) }
        i += 1usize
    }

    // 25-26: UTF-16 both ways.
    var wide: [32]u8 = zero
    let (d1, d1_error) = utf8.decode_utf16("a\x00\xac =\xd8\x00\xdez\x00", false, wide[0..])
    if d1_error != ok || !same(wide[..d1], "a\xe2\x82\xac\xf0\x9f\x98\x80z") { os.exit(25i32) }
    let (d2, d2_error) = utf8.decode_utf16("\x00a \xac\xd8=\xde\x00\x00z", true, wide[0..])
    if d2_error != ok || !same(wide[..d2], "a\xe2\x82\xac\xf0\x9f\x98\x80z") { os.exit(25i32) }
    let (d3, d3_error) = utf8.decode_utf16("\xff\xfea\x00\xac =\xd8\x00\xdez\x00", true, wide[0..])
    if d3_error != ok || !same(wide[..d3], "a\xe2\x82\xac\xf0\x9f\x98\x80z") { os.exit(25i32) }
    let (_, d4_error) = utf8.decode_utf16("\x00\xd8A\x00", false, wide[0..])
    let (_, d5_error) = utf8.decode_utf16("abc", false, wide[0..])
    if d4_error != utf8.Invalid || d5_error != utf8.Invalid { os.exit(25i32) }
    let (n1, n1_error) = utf8.encode_utf16("a\xe2\x82\xac\xf0\x9f\x98\x80z", false, wide[0..])
    if n1_error != ok || !same(wide[..n1], "a\x00\xac =\xd8\x00\xdez\x00") { os.exit(26i32) }
    let (n2, n2_error) = utf8.encode_utf16("a\xe2\x82\xac\xf0\x9f\x98\x80z", true, wide[0..])
    if n2_error != ok || !same(wide[..n2], "\x00a \xac\xd8=\xde\x00\x00z") { os.exit(26i32) }
    let (_, n3_error) = utf8.encode_utf16("abc", true, wide[0..2usize])
    if n3_error != utf8.TooSmall { os.exit(26i32) }

    try io.print("text gaps ok\n")
    ret ok
}
