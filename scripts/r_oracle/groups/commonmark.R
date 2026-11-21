# commonmark's markdown_html / markdown_xml / markdown_latex / markdown_man over every example of the
# CommonMark spec, the GFM extension examples (tables, strikethrough, autolink, tasklist, tagfilter),
# the smart punctuation examples and the cmark regression examples (scripts/r_oracle/data/commonmark,
# taken from the cmark-gfm test directory). A case holds the markdown ("in"), the renderer (fn) and
# the options (args: hardbreaks, smart, normalize, sourcepos, footnotes, width, extension mask where
# table=1 strikethrough=2 autolink=4 tagfilter=8 tasklist=16); the answer is the rendered text.
library(commonmark)

dir <- file.path(root, "scripts", "r_oracle", "data", "commonmark")
read_examples <- function(file) {
  lines <- readLines(file.path(dir, file), encoding = "UTF-8", warn = FALSE)
  out <- list(); state <- 0; inp <- character()
  for (l in lines) {
    if (state == 0 && grepl("^`{32} example", l)) { state <- 1; inp <- character(); next }
    if (state == 1 && l == ".") { state <- 2; next }
    if (state > 0 && grepl("^`{32}$", l)) { out[[length(out) + 1]] <- inp; state <- 0; next }
    if (state == 1) inp <- c(inp, l)
  }
  lapply(out, function(x) gsub("→", "\t", paste0(paste(x, collapse = "\n"), "\n"), fixed = TRUE))
}

ext_names <- c("table", "strikethrough", "autolink", "tagfilter", "tasklist")
exts <- function(mask) ext_names[bitwAnd(mask, 2^(0:4)) > 0]
render <- function(fn, text, hb, smart, norm, pos, foot, width, mask) {
  e <- if (mask == 0) FALSE else exts(mask)
  switch(fn,
    html = markdown_html(text, hardbreaks = hb, smart = smart, normalize = norm, sourcepos = pos, footnotes = foot, extensions = e),
    xml = markdown_xml(text, hardbreaks = hb, smart = smart, normalize = norm, sourcepos = pos, footnotes = foot, extensions = e),
    latex = markdown_latex(text, hardbreaks = hb, smart = smart, normalize = norm, footnotes = foot, width = width, extensions = e),
    man = markdown_man(text, hardbreaks = hb, smart = smart, normalize = norm, footnotes = foot, width = width, extensions = e))
}

cases <- list()
add <- function(fn, text, hb = 0, smart = 0, norm = 0, pos = 0, foot = 0, width = 0, mask = 0) {
  want <- render(fn, text, hb == 1, smart == 1, norm == 1, pos == 1, foot == 1, width, mask)
  Encoding(want) <- "UTF-8"
  cases[[length(cases) + 1]] <<- case(fn, c(hb, smart, norm, pos, foot, width, mask), want, input = text)
}

spec <- read_examples("spec.txt")
ext <- read_examples("extensions.txt")
smart <- read_examples("smart_punct.txt")
reg <- read_examples("regression.txt")

for (i in seq_along(spec)) {
  t <- spec[[i]]
  add("html", t)
  add("xml", t)
  add("latex", t)
  add("man", t)
  # every option at once: source positions, smart punctuation, hard breaks and all five extensions
  add("html", t, hb = 1, smart = 1, pos = 1, mask = 31)
  add("xml", t, smart = 1, pos = 1, mask = 31)
  if (i %% 3 == 0) add("latex", t, width = 20, smart = 1, mask = 31)
  if (i %% 3 == 1) add("man", t, width = 30, hb = 1, smart = 1, mask = 31)
}
for (t in c(ext, reg)) {
  add("html", t)
  add("html", t, mask = 31)
  add("html", t, mask = 31, pos = 1)
  add("xml", t, mask = 31)
  add("latex", t, mask = 31)
  add("man", t, mask = 31)
  add("html", t, mask = 1)
  add("html", t, mask = 2)
  add("html", t, mask = 4)
  add("html", t, mask = 8)
  add("html", t, mask = 16)
}
for (t in smart) {
  add("html", t, smart = 1)
  add("xml", t, smart = 1)
  add("latex", t, smart = 1)
  add("man", t, smart = 1)
  add("html", t, smart = 1, pos = 1)
  add("html", t)
}
emit("commonmark", "commonmark", list(cases))
