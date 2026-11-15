# cli's ANSI string operations on strings with SGR attributes, colours, hyperlinks and other CSI
# sequences, over ASCII, accented, wide, emoji and Hangul text. A case holds the input strings
# ("in"), the operation (fn) and its options (args); the answer is the strings joined by U+0001
# (numbers by ",").
library(cli)

E <- "\033"
pool <- c(
  "", "foo", "hello world", "  padded  ", "\t tab and\nnewline ",
  paste0(E, "[1mbold", E, "[22m plain"),
  paste0(E, "[31mred", E, "[39m"),
  paste0(E, "[1m", E, "[31mboth", E, "[39m", E, "[22m"),
  paste0(E, "[31;1mcombined", E, "[0m"),
  paste0("a", E, "[31mb", E, "[1mc", E, "[22md", E, "[39me"),
  paste0(E, "[38;5;100mx256", E, "[39m"),
  paste0(E, "[38;2;1;2;3mrgb", E, "[39m", E, "[48;2;10;20;30mbg", E, "[49m"),
  paste0(E, "[4munder", E, "[24m ", E, "[3mital", E, "[23m ", E, "[7minv", E, "[27m ", E, "[9mstrike", E, "[29m ",
         E, "[8mhid", E, "[28m ", E, "[2mfaint", E, "[22m ", E, "[5mblink", E, "[25m"),
  paste0(E, "]8;;https://x.org\007link", E, "]8;;\007 after"),
  paste0(E, "]8;id=1;https://x.org/a?b=c", E, "\\txt", E, "]8;;", E, "\\ tail"),
  paste0("a", E, "[2Kb", E, "[1Ac"),
  paste0(E, "[1;99mfoo", E, "[0m"),
  paste0(E, "[1mx", E, "[0my"),
  paste0(E, "[31ma", E, "[32mb", E, "[39m"),
  paste0(E, "[44;93mbg", E, "[0m ", E, "[101mbright", E, "[49m"),
  "héllo", "日本語", "\U0001F44D\U0001F3FD thumbs", "\U0001F1FA\U0001F1F8 flag",
  "é combining", "한글", "\U0001F468‍\U0001F469‍\U0001F467 family", "a​b",
  paste0(E, "[1m日本", E, "[22m \U0001F44D", E, "[31m éx", E, "[39m"),
  "<b>&amp;</b> & < >", paste0(E, "[1m<b>&", E, "[22m")
)
joined <- function(x) paste(as.character(x), collapse = "\001")
cases <- list()
add <- function(fn, args, input, want) cases[[length(cases) + 1]] <<- case(fn, args, want, input = input)

tf <- c(TRUE, FALSE)
for (s in pool) {
  for (sgr in tf) for (csi in tf) for (link in tf) {
    add("strip", c(sgr, csi, link), s, joined(ansi_strip(s, sgr = sgr, csi = csi, link = link)))
    add("has_any", c(sgr, csi, link), s, joined(ansi_has_any(s, sgr = sgr, csi = csi, link = link)))
  }
  types <- c("chars", "bytes", "width", "codepoints")
  for (t in seq_along(types)) add("nchar", t - 1, s, joined(ansi_nchar(s, type = types[t])))
  for (r in list(c(1, 3), c(2, 4), c(1, 1), c(3, 100), c(0, 2), c(5, 3), c(2, 2), c(1, 1000), c(4, 6)))
    add("substr", r, s, joined(ansi_substr(s, r[1], r[2])))
  for (keep in tf) add("simplify", keep, s, joined(ansi_simplify(s, csi = if (keep) "keep" else "drop")))
  for (esc in tf) for (keep in tf)
    add("html", c(esc, keep), s, joined(ansi_html(s, escape_reserved = esc, csi = if (keep) "keep" else "drop")))
  for (w in c("both", "left", "right")) add("trimws", match(w, c("both", "left", "right")) - 1, s, joined(ansi_trimws(s, w)))
  for (width in c(0, 5, 12, 30)) for (how in c("left", "center", "right")) for (ty in c("width", "chars"))
    add("align", c(width, match(how, c("left", "center", "right")) - 1, if (ty == "width") 2 else 0), s,
        joined(ansi_align(s, width = width, align = how, type = ty)))
  ascii <- all(utf8ToInt(s) < 128)   # R mangles astral characters in toupper() on Windows
  if (ascii) {
    add("case", 1, s, joined(ansi_toupper(s)))
    add("case", 0, s, joined(ansi_tolower(s)))
  }
}
# vectors: operations that look at the whole vector
vecs <- list(pool[c(2, 6, 7, 4)], pool[c(5, 1, 3)], pool[c(10, 4, 22, 8)])
for (v in vecs) {
  for (w in c("both", "left", "right")) add("trimws", match(w, c("both", "left", "right")) - 1, v, joined(ansi_trimws(v, w)))
  add("substr", c(2, 4), v, joined(ansi_substr(v, 2, 4)))
}
emit("ansi", "cli", list(cases))
