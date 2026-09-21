// `e.text.stem`: Porter (the published rules) and Lancaster agree with
// NLTK on the words of Porter's own examples and a hundred more (each
// compared in Python before it was written here), affix stripping takes
// the longest prefix and suffix repeatedly down to a minimum, and short
// output answers `TooSmall`. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.stem

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check(word: str, porter: str, lancaster: str) {
    var out: [64]u8 = zero
    let (p, p_error) = stem.porter(word, out[..])
    if p_error != ok || !same(p, porter) { os.exit(1i32) }
    let (l, l_error) = stem.lancaster(word, out[..])
    if l_error != ok || !same(l, lancaster) { os.exit(2i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    check("caresses", "caress", "caress")
    check("ponies", "poni", "pony")
    check("ties", "ti", "tie")
    check("caress", "caress", "caress")
    check("cats", "cat", "cat")
    check("feed", "feed", "fee")
    check("agreed", "agre", "agree")
    check("plastered", "plaster", "plast")
    check("bled", "bled", "bled")
    check("motoring", "motor", "mot")
    check("sing", "sing", "sing")
    check("conflated", "conflat", "confl")
    check("troubled", "troubl", "troubl")
    check("sized", "size", "siz")
    check("hopping", "hop", "hop")
    check("tanned", "tan", "tan")
    check("falling", "fall", "fal")
    check("hissing", "hiss", "hiss")
    check("fizzed", "fizz", "fizz")
    check("failing", "fail", "fail")
    check("filing", "file", "fil")
    check("happy", "happi", "happy")
    check("sky", "sky", "sky")
    check("relational", "relat", "rel")
    check("conditional", "condit", "condit")
    check("rational", "ration", "rat")
    check("valenci", "valenc", "valenc")
    check("hesitanci", "hesit", "hesitanc")
    check("digitizer", "digit", "digit")
    check("conformabli", "conform", "conformabl")
    check("radicalli", "radic", "radicall")
    check("differentli", "differ", "differentl")
    check("vileli", "vile", "vilel")
    check("analogousli", "analog", "analogousl")
    check("vietnamization", "vietnam", "vietnam")
    check("predication", "predic", "pred")
    check("operator", "oper", "op")
    check("feudalism", "feudal", "feud")
    check("decisiveness", "decis", "decid")
    check("hopefulness", "hope", "hop")
    check("callousness", "callous", "cal")
    check("formaliti", "formal", "formalit")
    check("sensitiviti", "sensit", "sensitivit")
    check("sensibiliti", "sensibl", "sensibilit")
    check("triplicate", "triplic", "triply")
    check("formative", "form", "form")
    check("formalize", "formal", "form")
    check("electriciti", "electr", "electricit")
    check("electrical", "electr", "elect")
    check("hopeful", "hope", "hop")
    check("goodness", "good", "good")
    check("revival", "reviv", "rev")
    check("allowance", "allow", "allow")
    check("inference", "infer", "inf")
    check("airliner", "airlin", "airlin")
    check("gyroscopic", "gyroscop", "gyroscop")
    check("adjustable", "adjust", "adjust")
    check("defensible", "defens", "defens")
    check("irritant", "irrit", "irrit")
    check("replacement", "replac", "replac")
    check("adjustment", "adjust", "adjust")
    check("dependent", "depend", "depend")
    check("adoption", "adopt", "adopt")
    check("homologou", "homolog", "homologou")
    check("communism", "commun", "commun")
    check("activate", "activ", "act")
    check("angulariti", "angular", "angularit")
    check("homologous", "homolog", "homolog")
    check("effective", "effect", "effect")
    check("bowdlerize", "bowdler", "bowdl")
    check("probate", "probat", "prob")
    check("rate", "rate", "rat")
    check("cease", "ceas", "ceas")
    check("controll", "control", "control")
    check("roll", "roll", "rol")
    check("generalization", "gener", "gen")
    check("oscillators", "oscil", "oscil")
    check("running", "run", "run")
    check("maximum", "maximum", "maxim")
    check("presumably", "presum", "presum")
    check("multiply", "multipli", "multiply")
    check("provision", "provis", "provid")
    check("owed", "ow", "ow")
    check("ear", "ear", "ear")
    check("saying", "sai", "say")
    check("crying", "cry", "cry")
    check("string", "string", "string")
    check("meant", "meant", "meant")
    check("cement", "cement", "cem")
    check("abilities", "abil", "abl")
    check("agreement", "agreement", "agr")
    check("believable", "believ", "believ")
    check("classification", "classif", "class")
    check("computers", "comput", "comput")
    check("dying", "dy", "dying")
    check("flies", "fli", "fli")
    check("generously", "gener", "gen")
    check("happiness", "happi", "happy")
    check("knives", "knive", "kniv")
    check("laboratories", "laboratori", "lab")
    check("monetary", "monetari", "monet")
    check("nationality", "nation", "nat")
    check("obviously", "obvious", "obvy")
    check("questioning", "question", "quest")
    check("readily", "readili", "ready")
    check("recognized", "recogn", "recogn")
    check("responsibilities", "respons", "respons")
    check("scientific", "scientif", "sci")
    check("stemming", "stem", "stem")
    check("technologies", "technologi", "technolog")
    check("universities", "univers", "univers")
    check("validation", "valid", "valid")
    check("waiting", "wait", "wait")
    check("yearly", "yearli", "year")
    check("zoology", "zoologi", "zoolog")
    check("a", "a", "a")
    check("be", "be", "be")
    check("it", "it", "it")
    check("the", "the", "the")
    check("is", "i", "is")
    check("was", "wa", "was")
    check("mind", "mind", "mind")
    check("kind", "kind", "kind")
    check("ugly", "ugli", "ug")
    check("consecutive", "consecut", "consecut")
    check("activities", "activ", "act")
    check("RUNNING", "run", "run")

    // 3: affix stripping and storage checks.
    var prefixes: [3]str = zero
    prefixes[0usize] = "un"
    prefixes[1usize] = "re"
    prefixes[2usize] = "anti"
    var suffixes: [3]str = zero
    suffixes[0usize] = "ness"
    suffixes[1usize] = "ly"
    suffixes[2usize] = "ful"
    if !same(stem.strip_affixes("unhelpfulness", prefixes[..], suffixes[..], 3usize), "help") { os.exit(3i32) }
    if !same(stem.strip_affixes("antirely", prefixes[..], suffixes[..], 3usize), "rely") { os.exit(3i32) }
    if !same(stem.strip_affixes("really", prefixes[..], suffixes[..], 2usize), "al") { os.exit(3i32) }
    if !same(stem.strip_affixes("really", prefixes[..], suffixes[..], 3usize), "ally") { os.exit(3i32) }
    if !same(stem.strip_affixes("ly", prefixes[..], suffixes[..], 1usize), "ly") { os.exit(3i32) }
    if !same(stem.strip_affixes("", prefixes[..], suffixes[..], 0usize), "") { os.exit(3i32) }
    var small: [4]u8 = zero
    let (_, p_room) = stem.porter("running", small[..])
    if p_room != stem.TooSmall { os.exit(3i32) }
    let (_, l_room) = stem.lancaster("running", small[..])
    if l_room != stem.TooSmall { os.exit(3i32) }
    let (empty, empty_error) = stem.lancaster("", small[..])
    if empty_error != ok || empty.len != 0usize { os.exit(3i32) }

    try io.print("text stem ok\n")
    ret ok
}
