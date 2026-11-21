# hunspell: the check, analyze, stem, suggest and find answers of the R package over its bundled
# en_US and en_GB dictionaries (tests/oracle/hunspell holds copies of the four files). A case is
# (dictionary: 0 en_US, 1 en_GB) with the word or text in "in"; check answers 1 or 0, the others
# answer text, one result per line. Words are drawn from the dictionaries, with their affixed
# forms, seeded misspellings, capitalisations, numbers, hyphens, abbreviations and apostrophes.
library(hunspell)

dicts <- list(dictionary("en_US"), dictionary("en_GB"))
set.seed(20261120)

stems <- function(f) {
  l <- readLines(f, encoding = "UTF-8", warn = FALSE)[-1]
  sub("/.*$", "", l)
}
base <- list(stems(system.file("dict", "en_US.dic", package = "hunspell")),
             stems(system.file("dict", "en_GB.dic", package = "hunspell")))
# words that are plain lower case ASCII letters
plain <- lapply(base, function(w) w[grepl("^[a-z]{3,12}$", w)])

mutate <- function(w) {
  n <- nchar(w)
  kind <- sample(8, 1)
  ch <- sample(letters, 1)
  i <- sample(n, 1)
  switch(kind,
    paste0(substr(w, 1, i - 1), substr(w, i + 1, n)),                      # drop a letter
    paste0(substr(w, 1, i), ch, substr(w, i + 1, n)),                      # add a letter
    paste0(substr(w, 1, i - 1), ch, substr(w, i + 1, n)),                  # replace a letter
    if (n > 2) { j <- sample(n - 1, 1); paste0(substr(w, 1, j - 1), substr(w, j + 1, j + 1), substr(w, j, j), substr(w, j + 2, n)) } else w,
    paste0(substr(w, 1, i), substr(w, i, i), substr(w, i + 1, n)),         # double a letter
    paste0(w, "s"),
    paste0(w, "ing"),
    paste0("un", w))
}

draw <- function(d, k) {
  p <- plain[[d + 1]]
  w <- sample(p, k)
  c(w, vapply(sample(p, k), mutate, ""), vapply(sample(p, k %/% 2), function(x) paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x))), ""),
    vapply(sample(p, k %/% 4), toupper, ""))
}

fixed <- c("dogs", "walking", "unhappily", "reread", "undoing", "Unhappy", "Dogs", "DOGS", "dog's", "hello", "Hello", "HELLO", "hELLO",
           "McDonald", "iPhone", "OpenOffice", "OPENOFFICE", "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st",
           "123rd", "1000th", "2th", "0th", "10", "3.14", "1,000", "12-34", "1..2", "foo-bar", "Foo-bar", "non-existent", "e.g.", "i.e.", "etc.",
           "Mr.", "Dr", "can't", "don't", "won't", "o'clock", "rock'n'roll", "café", "naïve", "résumé", "’tis", "don’t",
           "helo", "wrold", "speling", "alot", "teh", "dogz", "recieve", "definately", "seperate", "occured", "wich", "thier", "becuase",
           "acommodate", "accomodate", "neccessary", "untill", "tommorow", "goverment", "enviroment", "Wendsday", "Febuary", "dont", "cant",
           "didnt", "wouldnt", "theyre", "youre", "its", "colour", "color", "organise", "organize", "grey", "gray", "centre", "center",
           "analyse", "analyze", "aluminium", "aluminum", "whilst", "tyre", "tire", "kerb", "curb", "cheque", "check", "a", "I", "an", "xyzzy",
           "qwerty", "asdf", "aaaa", "zzzz", "the the", "", "   ", ".", "..", "-", "word.", "word..", "Word.", "WORD.", "a.b", "x-ray", "X-ray",
           "teh-dog", "walkin", "runing", "swiming", "stoping", "begining", "writting", "comming", "geting", "puting", "ran", "runned", "goed",
           "childs", "mans", "foots", "mouses", "sheeps", "datas", "informations", "advices", "furnitures", "an apple", "NASA", "nasa",
           "Nasa", "unix", "UNIX", "Unix", "paris", "Paris", "london", "London", "september", "September", "monday", "Monday")

words <- list(unique(c(fixed, draw(0, 140))), unique(c(fixed, draw(1, 140))))

cases <- list()
add <- function(fn, d, word, want) {
  cases[[length(cases) + 1]] <<- case(fn, d, want, input = enc2utf8(word))
}
lines <- function(x) paste(x, collapse = "\n")
for (d in 0:1) {
  dict <- dicts[[d + 1]]
  ws <- words[[d + 1]]
  chk <- hunspell_check(ws, dict = dict)
  an <- hunspell_analyze(ws, dict = dict)
  st <- hunspell_stem(ws, dict = dict)
  sg <- hunspell_suggest(ws, dict = dict)
  for (i in seq_along(ws)) {
    add("check", d, ws[i], as.integer(chk[i]))
    add("analyze", d, ws[i], lines(an[[i]]))
    add("stem", d, ws[i], lines(st[[i]]))
    add("suggest", d, ws[i], lines(sg[[i]]))
  }
}

texts <- c(
  "Hello wrold, this is a tset of the sentnce with don't and 3rd and e.g. foo_bar",
  "The quick brown fox jumps over the lazy dog.",
  "Teh quik brwon fox jumpd ovr teh lazzy dog.",
  "It's a well-known fact that rock'n'roll isn't dead; it's just resting.",
  "Visit http://example.com/pathh or write to nobody@exmaple.com for the detials.",
  "Colour, color, centre, center: whcih is rigth?",
  "café naïve résumé and some wrods",
  "He said “hello” and she answered ‘yes’, didnt she?",
  "1st 2nd 3rd 4th 11th 21st 1000th and 2th",
  "Mr. Smith's dog's bone: the dogs' bones.",
  "A sentence with   multiple    spaces\tand\ttabs\nand a newline.",
  "x = y + z; // a commnet",
  "&Agrave;la carte &eacute;clair &Egrave;",
  "foo-bar baz-qux non-existant e-mail",
  "", "   ", "!!!", "a", "I am", "twelve12 12twelve")
for (d in 0:1) {
  res <- hunspell_find(texts, dict = dicts[[d + 1]], ignore = character(0))
  for (i in seq_along(texts)) add("find", d, texts[i], lines(res[[i]]))
}
added <- sort(unique(c("wrold", "tset", "Xanadu", "frobnicate", "qwertz", "NeperLang", "e.mail", "don'tt", "naïvety", "zzyzx", "foo-bar-baz", "ALLCAPS", "McFoo", "dog")))
d3 <- dictionary("en_US", add_words = added)
cases[[length(cases) + 1]] <- case("added", 2, 0, input = enc2utf8(added))
aw <- c(added, paste0(added, "s"), toupper(added), tolower(added), paste0(toupper(substr(added, 1, 1)), substr(added, 2, nchar(added))),
        "Xanadus", "frobnicated", "frobnicating", "wrolds", "Wrold", "WROLD", "e.mails", "mail", "foo", "bar", "baz", "foo-bar", "frobnicat", "wrld", "Xanadoo",
        "tsets", "nepelang", "zzyzxs", "McFoos", "MCFOO", "mcfoo", "ALLCAP", "allcaps", "hello", "wrods", "dogz", "recieve")
aw <- unique(aw)
chk <- hunspell_check(aw, dict = d3); an <- hunspell_analyze(aw, dict = d3); st <- hunspell_stem(aw, dict = d3); sg <- hunspell_suggest(aw, dict = d3)
for (i in seq_along(aw)) {
  add("check", 2, aw[i], as.integer(chk[i])); add("analyze", 2, aw[i], lines(an[[i]]))
  add("stem", 2, aw[i], lines(st[[i]])); add("suggest", 2, aw[i], lines(sg[[i]]))
}
atx <- c("Hello wrold, this is a tset of frobnicate and the Xanadu with qwertz and NeperLang", "foo-bar-baz and e.mail and dog's dogs", "ALLCAPS allcaps AllCaps McFoo mcfoo")
fa <- hunspell_find(atx, dict = dictionary("en_US"), ignore = added)
fb <- hunspell_find(atx, dict = d3, ignore = character(0))
for (i in seq_along(atx)) { stopifnot(identical(fa[[i]], fb[[i]])); add("find", 2, atx[i], lines(fb[[i]])) }
fmts <- c("text", "man", "latex", "xml", "html")
ftexts <- c(
  "Some <b>bold</b> wrods and <a href=\"http://x.y/z\" title=\"a titel\">a link</a> with &amp; and &eacute;ntity, &apos;quoted&apos; don&apos;t",
  "<!-- a commnet --> text <script>var x = 'wrods';</script> <img alt=\"an imge\" src=\"a.png\"/> <pre>codee</pre> end",
  "<p class='mispeled'>Para wrods</p>\n<code>foo bar</code> and <kbd>ctrl</kbd> okk",
  "<![CDATA[ somthing ]]> afterr &Agrave;la",
  ".TH FOO 1\n.SH NAME\nfoo \\- a progrm \\fBbold\\fR text \\fIital\\fP wrods",
  ".B bold wrods\nnormal wrods here",
  "\\documentclass{article}\n\\begin{document}\nHello wrold \\cite{refone} and $x + y$ math \\emph{emphsis} % a commnet wrods\n\\end{document}",
  "\\section{Intro} Some textt \\textbf{bold wrods} \\label{sec:one} \\ref{sec:two} \\\\ new line \\$5 \\% perecent",
  "Plain textt with don't and ``quotes'' and wrods. 3rd and 2th.",
  "\\verb|wrods| and \\begin{verbatim} codee \\end{verbatim} okk \\[ a + b \\] endd \\input{filee} \\hspace{1cm} text",
  "<div title=\"hellp\">hello</div> <a title='wrold' href='x'>link</a> <img title=\"imge\" alt=\"hello\">")
for (d in 0:1) for (f in seq_along(fmts)) for (i in seq_along(ftexts)) {
  r <- hunspell_find(ftexts[i], format = fmts[f], dict = dicts[[d + 1]], ignore = character(0))
  cases[[length(cases) + 1]] <- case("find_f", c(d, f - 1), lines(r[[1]]), input = enc2utf8(ftexts[i]))
  r <- hunspell_parse(ftexts[i], format = fmts[f], dict = dicts[[d + 1]])
  cases[[length(cases) + 1]] <- case("parse_f", c(d, f - 1), lines(r[[1]]), input = enc2utf8(ftexts[i]))
}
emit("hunspell", "hunspell", list(cases))
