# R yaml::yaml.load on libyaml's 1.1 scalar rules: yes/no/on/off booleans, octal and hex integers,
# thousands commas, sexagesimal and timestamps (left as strings), the .na / .inf / .nan forms,
# `!!` tags, anchors and aliases, `<<` merge keys, key coercion and R's list simplification.
# A case is the YAML text ("in") and the loaded value written as a canonical string: ~ null,
# b:/i:/s"..." scalars, d:<ipe-754 hex> doubles, [a,b] vectors and lists, {"k"=v} named lists;
# a load error is ERR. as_yaml cases are `as.yaml(yaml.load(text))`.
library(yaml)

set.seed(11)
toks <- c(".na", ".real", ".integer", ".character", ".na.real", "0", "1", "2", "7", "8", "9", "12", "0x", "1F", "+", "-", ".", ",", ":", "e", "E", "x", "_", "NA", "na", "y", "Y", "n", "N", "yes", "Yes", "YES", "no", "No", "NO", "on", "On", "ON", "off", "Off", "OFF", "true", "True", "TRUE", "false", "False", "FALSE", "null", "Null", "NULL", "~", "inf", "Inf", "INF", "nan", "NaN", "NAN", "00", "05", "30", "59", "60", "<<", "=", "_integer_", "_real_", "_character_", "NA_integer_", "NA_real_", "NA_character_", "T", "F", "t", "f", "tRue", "0b1", "0o7", "1e3", "e+3", "e-3", "2001-01-01", "t", "T", "21:59")
words <- c(".na.real", ".na.integer", ".na.character", ".na",
  "NA", "NA_integer_", "NA_real_", "NA_character_", "NA_complex_", ".NA", "N/A", "nan", "NaN", "NAN", ".NaN", ".nan", ".NAN", ".Nan", ".inf", ".Inf", ".INF", ".iNf", "-.inf", "+.inf", "-.Inf", "-.INF", "+.INF", "inf", "Inf",
  "y", "Y", "n", "N", "yes", "Yes", "YES", "yEs", "no", "No", "NO", "nO", "on", "On", "ON", "oN", "off", "Off", "OFF", "oFF", "true", "True", "TRUE", "tRUE", "false", "False", "FALSE", "fALSE", "t", "f", "T", "F",
  "null", "Null", "NULL", "nULL", "~", "~~", "", "0", "-0", "+0", "00", "01", "07", "08", "0777", "0x", "0x1", "0x1F", "-0x1f", "+0xA,B", "0xg", "0X1F", "1,000", "1,,0", "0,7", "1,", "1.5,3", "0b1", "12", "-12", "+12", "1_000",
  "1:30", "1:30:00", "-1:30", "+1:30:15", "12:5", "1:05:09", "1:60", "60:30", "0:30", "1:30.5", "1:30:00.5", "190:20:30", "2001-12-14", "2001-12-14T21:59:43.1Z", "2001-12-14 21:59:43.10 -5", "2001-12-14t21:59:43.10-05:00", "2002-1-1", "1.", "1.5", "-1.5", "+1.5", ".5", "-.5", "+.5", "5.", "0.", "00.5", "1,0.5", "1.5e3", "1.5E3", "1.5e+3", "1.5E+3", "1.5e-3", "1.5E-3", "1e3", "1E3", "1e+3", "1e-3", "1.e+3", ".5e+3", ".5e3", "1.5e", "1.5e+", "1.5e+3.1", "1.5.5", "1..5", ".", "..", "-.", "+.", "1e5", "99999999999", "2147483647", "-2147483647", "2147483648", "-2147483648", "0x7FFFFFFF", "0x80000000", "0xFFFFFFFFFF", "07777777777", "017777777777", "1.7976931348623157e308", "1.7976931348623159e+308", "123456789012345678901234567890", "0.1", "0.30000000000000004", "3.14159265358979323846", "<<", "=", "<", "<<<", "==",
  "tru", "truee", "yess", "nul", "Nul", "nnull", "falsee", "NAN.", "NA ", "y ", "NAs", "N A", "4.9e-324", "2.2250738585072014e-308")
rnd <- vapply(1:4000, function(i) paste(sample(toks, sample(1:4, 1), replace = TRUE), collapse = ""), "")
corpus <- unique(c(words, rnd))

quote_js <- function(s) paste0('"', gsub("\n", "\\\\n", gsub('"', '\\\\"', gsub("\\\\", "\\\\\\\\", s))), '"')
hex <- function(x) paste(rev(as.character(writeBin(x, raw(), endian = "little"))), collapse = "")
canon <- function(v) {
  if (is.null(v)) return("~")
  if (is.list(v)) {
    if (length(v) == 0 && !is.null(names(v))) return("{}")
    if (!is.null(names(v))) return(paste0("{", paste0(quote_js(names(v)), "=", vapply(v, canon, ""), collapse = ","), "}"))
    return(paste0("[", paste(vapply(v, canon, ""), collapse = ","), "]"))
  }
  one <- function(x) {
    if (is.logical(x)) return(if (is.na(x)) "b:NA" else if (x) "b:TRUE" else "b:FALSE")
    if (is.integer(x)) return(if (is.na(x)) "i:NA" else paste0("i:", x))
    if (is.double(x)) return(paste0("d:", hex(x)))
    if (is.character(x)) return(if (is.na(x)) "s:NA" else paste0("s", quote_js(x)))
    stop("type")
  }
  if (length(v) == 1) return(one(v))
  paste0("[", paste(vapply(v, one, ""), collapse = ","), "]")
}
load_canon <- function(text) {
  r <- tryCatch(suppressWarnings(yaml.load(text)), error = function(e) "ERR")
  if (identical(r, "ERR")) "ERR" else canon(r)
}

# Syntax the loader rejects before any tag is chosen is not a scalar-rule question; the corpus
# keeps the strings that load.
scalars <- Filter(function(s) !identical(load_canon(paste0("k: ", s)), "ERR"), corpus)
cases <- lapply(scalars, function(s) {
  text <- paste0("k: ", s)
  case("load", numeric(0), load_canon(text), input = text)
})

docs <- c(
  "a: 1\nb: yes\nc: ~\nd: 0o17\ne: 0b11\nf: 017\ng: 1:30:00\nh: 2001-12-14\n",
  "- yes\n- no\n- on\n- off\n- y\n- n\n",
  "- 1\n- 2\n- 3\n", "- 1\n- 2.5\n", "- 1\n- a\n", "- 1\n- ~\n", "- yes\n- .na\n", "- .na.integer\n- 3\n", "- 1\n- .na.real\n",
  "- [1]\n- [2]\n", "- [1, 2]\n- [3]\n", "- [1, 2]\n- [3, 4]\n", "[]\n", "{}\n", "a: []\nb: {}\n", "[1]\n", "[x]\n", "[true, false]\n", "[1, 2, 3]\n", "[a, b, c]\n", "[1.5, 2, 3]\n",
  "- a: 1\n- b: 2\n", "- - 1\n  - 2\n- - 3\n",
  "1: a\ntrue: b\n2.5: c\n.na: d\nno: e\n", "0x10: hex\n011: oct\n~: nul\n",
  "a: 1\na: 2\n", "{a: 1, a: 2}", "a: &x 1\nb: *x\n", "- &a 1\n- &a 2\n- *a\n", "a: &x [1, 2]\nb: &x [3]\nc: *x\n",
  "a: &x\n  b: 1\nc: *x\nd:\n  <<: *x\n  e: 2\n", "- &a [1,2]\n- *a\n- !!str 12\n- !!float 3\n- &b hello\n- *b\n", "- [ &r 1, *r ]\n- &s\n  k: v\n- *s\n",
  "m: {<<: [{a: 1}, {a: 2, b: 3}], c: 4}\n", "- {a: 1, <<: {a: 2, b: 3}}\n", "a: &p {x: 1}\nb:\n  <<: *p\n  x: 9\n", "a: &p {x: 1}\nb:\n  x: 9\n  <<: *p\n  z: 2\n",
  "base: &base\n  name: hi\n  val: 1\nderived:\n  <<: *base\n  val: 2\n", "base: &b {k: 1}\nother: &o {j: 2}\nm:\n  <<: [*b, *o]\n  l: 3\n",
  "<<: 1\n", "a:\n  <<: [1, 2]\n", "a: *nope\n", "- *q\n", "a: [*q]\n",
  "a: !!int '12'\nb: !!str 012\nc: !!float 1e3\nd: !!bool yes\ne: !!bool maybe\nf: !!int\ng: !!float\nh: !!str\n",
  "a: !!float inf\nb: !!float .5\nc: !!float 12x\nd: !!int +7\ne: !!int -0\nf: !!int 0x1F\ng: !!int 2147483648\n",
  "a: !!str yes\nb: !!str ~\nc: !!str 1.5\nd: !!str .inf\n", "a: !!null foo\nb: !!null\n", "a: !!bool no\nb: !!bool on\nc: !!bool y\nd: !!bool 1\n",
  "a: !!binary aGk=\nb: !!timestamp 2001-01-01\nc: !foo bar\nd: !!map x\ne: !expr 1+2\n", "a: !!seq x\n", "a: !!omap x\n", "a: !!str [1]\n", "a: !!int {x: 1}\n", "a: !!seq [1, 2]\nb: !!map {x: 1}\nc: !!null [1]\n",
  "a: !!str\nb: !!null foo\nc: !custom [1,2]\n", "a: !!int \"12\"\nb: !!str \"yes\"\nc: !!float '1.5'\n",
  "a: \"yes\"\nb: 'no'\nc: \"12\"\nd: '~'\ne: \"\"\n", "a: |\n  one\n  two\nb: >\n  fold\n  ed\n",
  "a: 1 # comment\nb: yes # on\n", "--- \na: 1\n", "yes\n", "12\n", "~\n", "", "1.5\n", "- 0777\n- 0x1f\n- 1,000\n- 12e3\n",
  "a:\n  b:\n    c: [1, yes, ~]\n    d: {e: no}\n", "a: [1, [2, 3], {b: c}]\n", "[[1], [2]]\n", "[[1, 2], [3]]\n", "[[1, 2], [3, 4]]\n", "[[a], [b]]\n",
  "[1, 2.5, yes]\n", "[yes, no]\n", "[yes, 1]\n", "[1, 2, 3.5]\n", "[~, ~]\n", "[.na, .na]\n", "[.na, 1]\n"
)
# Anchors, aliases and explicit tags in more positions (sequence items, flow collections, nesting, redefinition,
# tags on collections and on already-typed scalars, the tags R's yaml knows: binary, set, omap, seq, map, str,
# int, float, bool, null, timestamp, merge, expr).
anchor_docs <- c(
  "a: &x 1\nb: &y 2\nc: [*x, *y]\n", "- &a 1\n- &b 2\n- [*a, *b]\n- {k: *a}\n", "a: &x hello\nb: *x\nc: *x\n", "a: &x yes\nb: *x\n", "a: &x ~\nb: *x\n",
  "a: &x 1.5\nb: *x\n", "a: &x 0x1F\nb: *x\n", "a: &x '12'\nb: *x\n", "a: &x \"q\"\nb: *x\n", "a: &x\n  - 1\n  - 2\nb: *x\n", "a: &x\n  k: v\nb: *x\nc: *x\n",
  "a: &x {k: v}\nb: [*x, *x]\n", "a: &x [1, [2, 3]]\nb: *x\n", "- &a {k: 1}\n- &b [*a]\n- *b\n", "a: &x 1\na: &x 2\nb: *x\n", "a: &x 1\nb: &x 2\nc: *x\n",
  "- &x a\n- &x b\n- *x\n- *x\n", "a: &x-y 1\nb: *x-y\n", "a: &x_y 1\nb: *x_y\n", "a: &1 one\nb: *1\n", "a: &X 1\nb: *x\n", "a: &x\nb: *x\n", "a: &x !!str 12\nb: *x\n",
  "a: !!str &x 12\nb: *x\n", "a: &x !!int '12'\nb: *x\n", "a: &x [1, 2]\nb: &y *x\n", "a: *x\n", "a: &x *x\n", "a: [&x 1, &y 2, *y, *x]\n", "a: {&k key: v}\n",
  "a: {k: &x v, j: *x}\n", "- - &x 1\n  - *x\n- *x\n", "x: &anc\n  a: 1\n  b: 2\ny:\n  <<: *anc\nz:\n  <<: *anc\n  a: 3\n", "x: &a {p: 1}\ny: &b {q: 2}\nz:\n  <<: [*a, *b]\n",
  "x: &a {p: 1}\nz: {<<: *a, r: 3}\n", "- &a {p: 1}\n- <<: *a\n  q: 2\n", "a: &x [1, 2]\nb: [*x, *x]\n", "a: &x 1\nb: {*x : 2}\n", "k: &long_anchor_name value with spaces\nj: *long_anchor_name\n",
  "a: [&x 1, *x, &x 2, *x]\n", "a: &x\n  - &y 1\n  - *y\nb: *x\n", "&x a: 1\n", "a: &x 12\nb: !!str *x\n"
)
tag_docs <- c(
  "a: !!binary aGVsbG8=\n", "a: !!binary |\n  aGVsbG8=\n", "a: !!binary 'AAEC'\n", "a: !!binary \"\"\n", "a: !!binary x\n", "- !!binary aGk=\n- !!binary d29ybGQ=\n",
  "a: !!set {x, y}\n", "a: !!set {x: , y: }\n", "a: !!set [x, y]\n", "a: !!set\n  ? x\n  ? y\n", "a: !!omap [{x: 1}, {y: 2}]\n", "a: !!omap\n  - x: 1\n  - y: 2\n",
  "a: !!omap {x: 1}\n", "a: !!seq [1, 2, 3]\n", "a: !!seq\n  - 1\n  - 2\n", "a: !!seq {x: 1}\n", "a: !!seq 5\n", "a: !!map {x: 1, y: 2}\n", "a: !!map\n  x: 1\n  y: 2\n", "a: !!map [1, 2]\n",
  "a: !!map 5\n", "!!map {x: 1}\n", "!!seq [1, 2]\n", "!!str 12\n", "!!int '7'\n", "!!float 3\n", "!!bool yes\n", "!!null ~\n", "- !!str 1\n- !!int '2'\n- !!float '3.5'\n- !!bool 'yes'\n",
  "a: !!str [1, 2]\n", "a: !!str {x: 1}\n", "a: !!int [1]\n", "a: !!float {x: 1}\n", "a: !!bool [yes]\n", "a: !!str\n  - 1\n", "a: !!str |\n  text\n", "a: !!int |\n  12\n",
  "a: !!timestamp 2001-12-14\nb: !!timestamp 2001-12-14t21:59:43.10-05:00\nc: !!timestamp foo\n", "a: !!float 1:30\nb: !!int 1:30\nc: !!float .nan\nd: !!float -.inf\n",
  "a: !!int 0b101\nb: !!int 0o17\nc: !!int 017\nd: !!int 1_000\ne: !!int 1,000\n", "a: !!float 1_000.5\nb: !!float 1,000.5\nc: !!float 0x1F\n",
  "a: !!bool Y\nb: !!bool N\nc: !!bool TRUE\nd: !!bool off\ne: !!bool 0\n", "a: !!null ''\nb: !!null null\nc: !!null 0\n", "a: !!str ''\nb: !!str null\nc: !!str 0x1F\n",
  "a: !foo 1\nb: !bar [1, 2]\nc: !baz {x: 1}\n", "a: !foo\nb: !foo bar\nc: !<tag:x.org,2000:foo> 1\n", "a: !expr 1+2\nb: !expr [1, 2]\n", "a: !!merge x\n", "a: !!python/none ''\n",
  "a: !e 'x'\nb: !r 1\n", "- !!str\n- !!int\n- !!null\n- !!bool\n", "a: ! 12\nb: !! 12\n", "a: !!str &x 12\nb: !!int *x\n", "a: &x !!str 12\nb: !!int *x\n", "a: !!int 12 # c\n",
  "a: !!seq\n- 1\n- 2\n", "a: !!set\n  x: 1\n  y: 2\n", "a: !!omap\n  x: 1\n", "a: !!binary\n  aGk=\n", "a: !!str\n  hello\n", "a: !!int\n  12\n",
  "[!!str 1, !!int '2', !!float '3', !!bool 'yes', !!null '']\n", "{a: !!str 1, b: !!int '2'}\n", "- !!seq [a]\n- !!map {b: c}\n", "a: !!map {}\nb: !!seq []\n"
)
docs <- c(docs, anchor_docs, tag_docs)
cases <- c(cases, lapply(docs, function(text) case("load", numeric(0), load_canon(text), input = text)))

as_text <- function(text) tryCatch(suppressWarnings(as.yaml(yaml.load(text))), error = function(e) "ERR")
as_docs <- c(
  "a: 1\nb: yes\nc: ~\nd: no\ne: 1.5\nf: text\n", "- 1\n- 2\n- 3\n", "- 1.5\n- 2\n", "- a\n- b\n", "- yes\n- no\n", "[]\n", "{}\n", "a: []\nb: {}\n",
  "a: 'yes'\nb: 'no'\nc: '12'\nd: '~'\ne: ''\nf: 'null'\ng: '1.5'\nh: 'on'\n", "a: \"1:30\"\nb: 1:30\nc: 2001-12-14\nd: 0o17\n",
  "a: .inf\nb: -.inf\nc: .nan\nd: .na\ne: .na.real\nf: .na.integer\n", "- .na\n- 1\n", "- .na.real\n- 1.5\n",
  "a:\n  b:\n    c: 1\n  d: [1, 2]\n", "- a: 1\n  b: 2\n- c: 3\n", "- - 1\n  - 2\n- - 3\n",
  "x: 1e10\ny: 0.1\nz: 100000\nw: 123456.789\nv: 1e-5\nu: 1e15\nt: 0.0001\ns: 3.14159265358979\n",
  "a: 0.5\nb: 1e3\nc: 12345678901234.5\nd: -2.5\ne: 1.0e+3\n", "a: 1e300\nb: 1.5e-30\nc: -1e20\nd: 1.0e+100\ne: 123456789.123\nf: 0.00001234567891\n",
  "a: 2001-12-14\nb: 2001-12-14t21:59:43.10-05:00\nc: 2001-12-14 21:59:43.10 -5\nd: 2002-1-1\ne: 2001-12-14 21:59:43 Z\nf: 190:20:30\ng: 1:30.5\n",
  "a: 'a: b'\nb: 'a #b'\nc: \"x\"\nd: 'it''s'\ne: '- x'\nf: '? y'\ng: '@z'\nh: 'x:'\n",
  "a: |\n  one\n  two\nb: |-\n  one\n  two\n", "a: |+\n  one\n  two\n\nb: 1\n",
  "y: 1\nn: 2\nyes: 3\nnull: 4\n~: 5\nt: 6\n", "a: &x [1, 2]\nb: *x\n", "base: &b {k: 1}\nd:\n  <<: *b\n  j: 2\n",
  "a: !!str 12\nb: !!int '5'\nc: !!float 2\n", "a: hello world\nb: foo bar baz\nc: ' lead'\nd: 'trail '\n",
  "key with space: 1\n'1': 2\n'yes': 3\n", "a: \"tab\\there\"\nb: \"nl\\nx\"\n", "a: 'x\\y'\nb: \"q\\\"uote\"\n"
)
cases <- c(cases, lapply(as_docs, function(text) case("as_yaml", numeric(0), as_text(text), input = text)))
cases <- c(cases, lapply(scalars, function(s) {
  text <- paste0("k: ", s)
  case("as_yaml", numeric(0), as_text(text), input = text)
}))
# random doubles across the fixed and exponent forms, rounding at the 8th significant digit
set.seed(23)
nums <- c(runif(150, -1000, 1000), 10^runif(250, -12, 14) * sample(c(-1, 1), 250, TRUE), 10^runif(60, -300, 300), round(runif(60), sample(1:9, 60, TRUE)), c(0.5, 0.25, 1.25, 12345678.5, 0.00001, 0.0001, 9999999.5, 10000000, 99999.995, 1.00000005, 1.00000015, 2.5e-5, 1/256, 3/256, 5/256, 1/128 + 1/256, 12345678.5, 123456785, 0.00390625 * 1e3, 123456789012345678))
cases <- c(cases, lapply(nums, function(x) {
  text <- paste0("k: ", sprintf("%.17g", x))
  case("as_yaml", numeric(0), as_text(text), input = text)
}))
cases <- c(cases, lapply(split(nums, rep(1:30, length.out = length(nums))), function(v) {
  text <- paste0("[", paste(sprintf("%.17g", v), collapse = ", "), "]\n")
  case("as_yaml", numeric(0), as_text(text), input = text)
}))
# strings the emitter has to decide a style for, written as double-quoted YAML
yq <- function(s) {
  cps <- utf8ToInt(s)
  body <- vapply(cps, function(c) {
    if (c == 92) "\\\\" else if (c == 34) "\\\"" else if (c == 10) "\\n" else if (c == 9) "\\t" else if (c < 32 || c == 127) sprintf("\\x%02X", c) else intToUtf8(c)
  }, "")
  paste0("\"", paste(body, collapse = ""), "\"")
}
styled <- c("a'b", "a\"b", "@x", "%x", "!x", "x #y", "x#y", "a: b", "a:b", "[x]", "x,y", "- x", "-x", "'x'", "`x`", "a  b", "x ", " x", "&a", "*a", "|", ">", "{", "x}", "...", "---", "--- x", "?", "? x", "?x", ":", ": x", ":x", "-", "#", "#x", "a b", "é", "日本語", "a b", "tab\there", "x\ny", "x\n", "x\n\n", "\nx", " lead\nx", "a\n b", "a \nb", "a\n\nb", "back\\slash", "q\"uote", "nul\001x", "\u007f", "yes please", "No.", "nullx", "1.5x", "0x", "1 2", "true story", "a,b", "a;b", "a=b", "a|b", "a>b", "<<", "=", "~", "~x", ".", "..", "1,0", "10:30", "10:30pm", "2001-12-14x", "1e5", ".5e3", "abc def ghi")
cases <- c(cases, lapply(styled, function(s) {
  text <- paste0("k: ", yq(s))
  case("as_yaml", numeric(0), as_text(text), input = text)
}))

emit("yaml", "yaml", list(cases))
