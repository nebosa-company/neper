# R's strwrap and cli's ansi_strwrap, ansi_strsplit and ansi_strtrim. A case holds the strings in
# "in" and the options in args; the answer is the lines (or pieces) joined by U+0001, with a
# leading count for strsplit so an empty result differs from one empty piece.
library(cli)
set.seed(20261115)

E <- "\033"
joined <- function(x) paste(as.character(x), collapse = "\001")
counted <- function(x) paste0(length(x), ":", joined(x))
cases <- list()
add <- function(fn, args, input, want) cases[[length(cases) + 1]] <<- case(fn, args, want, input = input)

lorem <- "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs! How vexingly quick daft zebras jump?  Two spaces follow this one."
plain <- c(
  "", " ", "word", "two words", "  leading and trailing  ", lorem,
  "One.  Two!  Three?  Four", "Sentence end. Single space. Another", "tab\tseparated\twords here",
  "first paragraph here\n\nsecond paragraph here", "p1\n \n \np2\n\n\n\np3", "a\nb\nc", "para one.\n\n",
  "\n\nstarts with break", "quoted. \"next\" (end.) more 'x.' tail", "long_unbreakable_token_that_exceeds_any_small_width and short",
  "héllo wörld naïve façade", "日本語 の テキスト です", "ab 日本語日本語日本語 cd",
  "x\fform feed\fthree", "\fstart", "end\f", "a\f\fb"
)
styled <- c(
  paste0(E, "[31mred text that goes on for a while and wraps", E, "[39m after the red"),
  paste0("plain ", E, "[1mbold start ", E, "[31mred and bold", E, "[39m bold only", E, "[22m end of line here"),
  paste0(E, "[1m", E, "[31mfull line of both styles spanning many words in a row", E, "[39m", E, "[22m"),
  paste0("one. ", E, "[32mtwo.", E, "[39m  three. four five"),
  paste0(E, "]8;;https://x.org\007link text that is long enough to wrap", E, "]8;;\007 trailing words"),
  paste0(E, "[4munder", E, "[24m ", E, "[3mital", E, "[23m  ", E, "[9mstrike", E, "[29m  words"),
  paste0(E, "[38;5;100m256 color words here and there", E, "[39m ", E, "[48;2;1;2;3mbg words", E, "[49m"),
  paste0(E, "[31mpara one text", E, "[39m\n\n", E, "[32mpara two text", E, "[39m"),
  paste0("a", E, "[31mb c", E, "[39md e f", E, "[1m g h", E, "[22m i"),
  paste0(E, "[31m日本語 のテキスト", E, "[39m です 終わり")
)
wrap_pool <- c(plain, styled)
grid <- expand.grid(width = c(1, 2, 5, 10, 17, 30, 80), indent = c(0, 3), exdent = c(0, 2))
for (s in wrap_pool) for (i in seq_len(nrow(grid))) {
  g <- grid[i, ]
  if (!grepl(E, s, fixed = TRUE)) add("strwrap", c(g$width, g$indent, g$exdent), s, joined(base::strwrap(s, g$width, g$indent, g$exdent)))
  add("ansi_strwrap", c(g$width, g$indent, g$exdent), s, joined(ansi_strwrap(s, g$width, g$indent, g$exdent)))
}

split_pool <- c(
  "a-b--c-d", "--lead-and-trail--", "nodelimiter", "", "a b  c", "one, two,three ,four", "x1y22z333",
  paste0(E, "[31mred-", E, "[39m", E, "[32mgreen-", E, "[39mblue"),
  paste0(E, "[1mbold--text--here", E, "[22m"), "aXbXXc", "héllo-wörld-ü",
  paste0(E, "]8;;https://x.org\007a-b", E, "]8;;\007-c")
)
splits <- list(list("-", FALSE), list("[-]+", FALSE), list(" ", TRUE), list(",", TRUE), list("", FALSE), list("\\s+", FALSE),
               list("[0-9]", FALSE), list("X", TRUE), list("-", TRUE), list("[a-c]", FALSE), list("b|c", FALSE))
for (s in split_pool) for (sp in splits)
  add("ansi_strsplit", c(as.numeric(sp[[2]])), c(s, sp[[1]]), counted(ansi_strsplit(s, sp[[1]], fixed = sp[[2]])[[1]]))

trim_pool <- c("", "short", lorem, "日本語のテキストです", paste0(E, "[31m", lorem, E, "[39m"),
               paste0("a", E, "[1mbold and long text here", E, "[22m tail"), "héllo wörld naïve",
               paste0(E, "]8;;https://x.org\007link text that is long", E, "]8;;\007 after"))
ells <- c("…", "...", "", ">>")
for (w in c(0, 1, 2, 3, 5, 8, 12, 20, 60)) for (el in ells) {
  vs <- c(list(trim_pool), lapply(seq_along(trim_pool), function(i) trim_pool[i]))
  for (v in vs) {
    r <- tryCatch(ansi_strtrim(v, w, el), error = function(e) NULL)
    if (!is.null(r)) add("ansi_strtrim", w, c(el, v), joined(r))
  }
}
emit("ansiwrap", "cli", list(cases))
