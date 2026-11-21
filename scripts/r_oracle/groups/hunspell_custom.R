# hunspell with small hand-written dictionaries that exercise what the English ones do not: long,
# numeric and UTF-8 flag types, OCONV, MAP, KEY, anchored REP, BREAK, IGNORE, KEEPCASE,
# FORBIDDENWORD, NOSUGGEST, NEEDAFFIX, WARN, SUGSWITHDOTS, NOSPLITSUGS, ONLYMAXDIFF, FULLSTRIP,
# COMPOUNDRULE with ? and *, and prefix/suffix cross products. The dictionary files are written
# to tests/oracle/hunspell/ by this script and read back by the fixture. A case is (dictionary
# number) with the word in "in"; check answers 1 or 0, the others one result per line.
library(hunspell)

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."))
dir <- file.path(root, "tests", "oracle", "hunspell")

writeu <- function(path, x) { con <- file(path, "wb"); writeLines(enc2utf8(x), con, useBytes = TRUE); close(con) }

c0_aff <- c("SET UTF-8", "FLAG long", "TRY aeioutrnslEAI", "KEY qwertyuiop|asdfghjkl|zxcvbnm", "WORDCHARS ’-", "IGNORE ·",
  "KEEPCASE Kc", "FORBIDDENWORD Fw", "NOSUGGEST Ns", "NEEDAFFIX Na", "WARN Wr", "SUGSWITHDOTS", "MAXNGRAMSUGS 3", "MAXDIFF 5",
  "ICONV 1", "ICONV ’ '", "OCONV 2", "OCONV ' ’", "OCONV ae æ",
  "MAP 3", "MAP aáà", "MAP eéè", "MAP (ss)ß",
  "REP 5", "REP ^teh the", "REP ie$ y", "REP f ph", "REP ^_a a_the", "REP ough uff",
  "BREAK 3", "BREAK -", "BREAK ^#", "BREAK #$",
  "PFX Re Y 1", "PFX Re 0 re .", "PFX Un Y 1", "PFX Un 0 un [^aeiou]",
  "SFX Ss Y 2", "SFX Ss y ies [^aeiou]y", "SFX Ss 0 s [^y]",
  "SFX Ng Y 2", "SFX Ng e ing e", "SFX Ng 0 ing [^e]",
  "SFX Ed N 2", "SFX Ed e ed e", "SFX Ed 0 ed [^e]",
  "SFX Ly Y 1", "SFX Ly 0 ly .", "SFX Mm Y 1", "SFX Mm 0 's .")
c0_dic <- c("40", "walk/SsNgEdRe", "run/SsNg", "carry/SsRe", "happy/UnLy", "believe/NgReSs", "ache/Ss", "Paris/Kc", "Berlin/Mm",
  "NASA/Kc", "iPhone/Kc", "OpenOffice.org", "e-mail/Ss", "foo/Fw", "bar/Ns", "needy/Na", "stuff/Wr", "quick", "fox/Ss", "jump/SsNgEd",
  "over", "lazy/Ly", "dog/SsMm", "phone/Ss", "the", "a", "the lazy", "straße/Ss", "café/Ss", "naïve", "color", "tough/Ly",
  "stuffy", "ough", "me·ow", "hello", "world", "Hello", "hot", "hat")

c1_aff <- c("SET UTF-8", "FLAG num", "TRY abcdefghijklmnopqrstuvwxyz", "COMPOUNDMIN 2", "ONLYINCOMPOUND 99", "FULLSTRIP", "NOSPLITSUGS",
  "ONLYMAXDIFF", "MAXNGRAMSUGS 2", "COMPOUNDRULE 5", "COMPOUNDRULE 1*2?3", "COMPOUNDRULE (4)(5)", "COMPOUNDRULE (6)?(7)*", "COMPOUNDRULE (1)*(2)?(3)", "COMPOUNDRULE (4)*(5)?(6)",
  "REP 2", "REP a e", "REP y ie",
  "PFX 10 Y 1", "PFX 10 0 re .", "PFX 11 N 1", "PFX 11 0 pre .",
  "SFX 20 Y 2", "SFX 20 0 s [^s]", "SFX 20 0 es s", "SFX 21 Y 1", "SFX 21 y ied y", "SFX 22 N 1", "SFX 22 0 er .")
c1_dic <- c("30", "cat/20,10", "box/20,11", "fly/21,22,10", "play/22", "one/1", "two/2", "three/3", "a/1,2", "b/2,3", "c/3", "d/4", "e/5", "x/6", "y/7",
  "ab/1,2,3", "ba/4,5", "stem/99", "tree/20", "bus/20", "run/22", "dry/21", "dog", "frog", "tiger", "lion/20", "bear", "fish")

c2_aff <- c("SET UTF-8", "FLAG UTF-8", "TRY áéíóúőűabcdefghijklmnopqrstuvwxyz", "WORDCHARS -", "FORBIDDENWORD ß",
  "ICONV 2", "ICONV ch c", "ICONV ph f", "OCONV 1", "OCONV c ch",
  "PFX Á Y 1", "PFX Á 0 meg .", "SFX É Y 2", "SFX É 0 ért [^aeiouáé]", "SFX É 0 t [aeiouáé]",
  "SFX Ő N 1", "SFX Ő ő ek ő")
c2_dic <- c("18", "ház/ÁÉ", "kert/ÁÉ", "nő/ŐÉ", "idő/Ő", "fa/É", "szem", "kéz/É", "alma",
  "kar/Á", "béka", "kör", "körül", "szép", "szépül", "foé", "pho", "foo/ß")

c3_aff <- c("SET UTF-8", "TRY abcdefghijklmnopqrstuvwxyz", "COMPOUNDFLAG X", "COMPOUNDBEGIN b", "COMPOUNDMIDDLE m", "COMPOUNDEND e",
  "COMPOUNDPERMITFLAG P", "COMPOUNDFORBIDFLAG F", "COMPOUNDROOT R", "COMPOUNDMIN 2", "COMPOUNDWORDMAX 3", "CHECKCOMPOUNDDUP", "CHECKCOMPOUNDREP",
  "CHECKCOMPOUNDTRIPLE", "SIMPLIFIEDTRIPLE", "CHECKCOMPOUNDCASE", "ONLYINCOMPOUND O", "NEEDAFFIX N", "FORBIDDENWORD W",
  "REP 2", "REP ss s", "REP ie y",
  "PFX A Y 1", "PFX A 0 un/P .", "SFX S Y 2", "SFX S 0 s/P [^y]", "SFX S y ies/P y", "SFX T N 1", "SFX T 0 ed/F .")
c3_dic <- c("40", "foo/X", "bar/XS", "baz/XA", "sun/bS", "flower/mS", "pot/e", "house/eX", "fire/b", "work/eT", "shop/eS", "ice/bm", "cream/e",
  "ball/X", "lamp/X", "sea/X", "son/X", "side/X", "show/Xe", "girl/R", "friend/RS", "ship/X", "mate/e", "man/XS", "Moon/X", "light/X", "hand/bX",
  "bag/e", "spy/XS", "story/XS", "tell/X", "er/O", "ing/O", "do/XN", "wrong/XW", "sheep/X", "free/X", "dom/e", "sit/X", "ting/e")

c4_aff <- c("SET UTF-8", "TRY abcdefghijklmnopqrstuvwxyz", "NEEDAFFIX N", "PFX A Y 1", "PFX A 0 re/S .", "PFX B Y 1", "PFX B 0 un .",
  "SFX S Y 1", "SFX S 0 s .", "SFX D Y 1", "SFX D 0 ed/S .", "SFX G Y 1", "SFX G 0 ing/DS .", "SFX E N 1", "SFX E 0 ness/S .",
  "SFX H Y 2", "SFX H e ish/E e", "SFX H 0 ish/E [^e]")
c4_dic <- c("12", "walk/ADG", "hope/ADGH", "jump/DGB", "red/N", "dull/HB", "good/HE", "fool/H", "grey/ABS", "kind/E", "ink/G", "stem/AB")
c5_aff <- c("SET UTF-8", "TRY abcdefghijklmnopqrstuvwxyz", "AF 3", "AF AB", "AF B", "AF ABC", "AM 2", "AM po:noun is:plur", "AM po:verb",
  "PFX A Y 1", "PFX A 0 re .", "PFX B Y 1", "PFX B 0 un/2 .", "SFX C Y 2", "SFX C 0 s . 1", "SFX C 0 ing . 2")
c5_dic <- c("5", "walk/1", "run/2", "jump/3", "dog/3", "cat")
writeu(file.path(dir, "custom5.aff"), c5_aff); writeu(file.path(dir, "custom5.dic"), c5_dic)
writeu(file.path(dir, "custom4.aff"), c4_aff); writeu(file.path(dir, "custom4.dic"), c4_dic)
writeu(file.path(dir, "custom3.aff"), c3_aff); writeu(file.path(dir, "custom3.dic"), c3_dic)
writeu(file.path(dir, "custom0.aff"), c0_aff); writeu(file.path(dir, "custom0.dic"), c0_dic)
writeu(file.path(dir, "custom1.aff"), c1_aff); writeu(file.path(dir, "custom1.dic"), c1_dic)
writeu(file.path(dir, "custom2.aff"), c2_aff); writeu(file.path(dir, "custom2.dic"), c2_dic)

dicts <- lapply(0:5, function(i) dictionary(file.path(dir, sprintf("custom%d.dic", i)), affix = file.path(dir, sprintf("custom%d.aff", i)), cache = FALSE))
base <- lapply(list(c0_dic, c1_dic, c2_dic, c3_dic, c4_dic, c5_dic), function(l) sub("/.*$", "", l[-1]))

forms <- function(w) c(w, paste0(w, "s"), paste0(w, "es"), paste0(w, "ing"), paste0(w, "ed"), paste0(w, "ly"), paste0(w, "'s"), paste0("re", w), paste0("un", w),
                      paste0("pre", w), paste0(w, "er"), paste0(w, "ied"), paste0(w, "’s"), paste0("meg", w), paste0(w, "ért"), paste0(w, "t"),
                      paste0(w, "ek"), paste0(toupper(substr(w, 1, 1)), substr(w, 2, nchar(w))), toupper(w), paste0(w, "."), paste0(w, "-", w), paste0(w, "#"),
                      paste0("#", w), paste0(w, " ", w), paste0(w, "·"))
mut <- function(w) {
  n <- nchar(w)
  if (n < 2) return(paste0(w, "x"))
  i <- sample(n, 1)
  switch(sample(6, 1), substr(w, 1, i - 1), paste0(substr(w, 1, i), sample(letters, 1), substr(w, i + 1, n)),
         paste0(substr(w, 1, i - 1), sample(letters, 1), substr(w, i + 1, n)),
         if (n > 2) { j <- sample(n - 1, 1); paste0(substr(w, 1, j - 1), substr(w, j + 1, j + 1), substr(w, j, j), substr(w, j + 2, n)) } else w,
         paste0(w, substr(w, n, n)), paste0(substr(w, 1, i), substr(w, i, i), substr(w, i + 1, n)))
}
set.seed(20261121)
cases <- list()
add <- function(fn, d, word, want) cases[[length(cases) + 1]] <<- case(fn, d, want, input = enc2utf8(word))
lines <- function(x) paste(x, collapse = "\n")
extra <- c("teh", "Teh", "phone", "fone", "ought", "strasse", "STRASSE", "Straße", "straSSe", "cafe", "café", "CAFÉ", "cafes", "naive", "paris", "PARIS",
           "Paris", "nasa", "Nasa", "NASA", "iphone", "iPhone", "IPHONE", "foo", "Foo", "bar", "needy", "stuff", "stuffs", "a the", "athe", "thelazy", "lazyly",
           "1", "11", "123", "1a2", "12a", "112", "1 2", "34", "45", "67", "6", "7", "677", "767", "one", "onetwo", "onetwothree", "ab", "abab", "ba", "baba", "abba",
           "meow", "me·ow", "mew", "á", "mehaz", "megház", "házt", "házért", "chaz", "phaz", "szépül", "körül", "nőek", "időek")
for (d in 0:5) {
  p <- base[[d + 1]]
  if (d == 5) extra <- c(extra, unlist(lapply(p, function(x) c(paste0(x, c("s", "ing", "ings", "ss")), paste0("re", x, c("", "s", "ing")), paste0("un", x, c("", "s", "ing")), paste0("reun", x)))))
  ws <- unique(c(extra, unlist(lapply(sample(p, min(length(p), 14)), forms)), vapply(sample(p, min(length(p), 25), TRUE), mut, "")))
  if (d == 4) {
    sfx <- c("s", "ed", "eds", "ing", "ings", "ness", "nesses", "ish", "ishness", "ishnesses", "d", "ishes", "edish")
    ws <- unique(c(ws, unlist(lapply(p, function(x) c(paste0(x, sfx), paste0("re", x, sfx), paste0("un", x, sfx), paste0("reun", x), paste0("unre", x))))))
  }
  if (d == 3) {
    q <- p[nchar(p) > 1]
    pairs <- unlist(lapply(1:260, function(i) { k <- sample(q, if (i %% 3 == 0) 3 else 2, TRUE); paste(k, collapse = "") }))
    ws <- unique(c(ws, pairs, vapply(pairs[1:60], function(x) paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x))), ""),
                   vapply(pairs[61:100], function(x) paste0(x, "s"), ""), vapply(pairs[101:140], function(x) paste0("un", x), ""),
                   vapply(pairs[141:180], mut, ""), c("balllamp", "ballamp", "ballamps", "fireman", "firemen", "sunflower", "sunflowers",
                   "seaside", "wrongdo", "dowrong", "sheepfree", "freedom", "freesit", "sitting", "bagman", "Moonlight", "moonLight", "moon-light")))
  }
  dict <- dicts[[d + 1]]
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
  tx <- c(paste(ws[1:8], collapse = " "), paste(ws[9:20], collapse = ", "), paste(ws[21:30], collapse = "-"), paste(sample(ws, 12), collapse = ". "))
  fd <- hunspell_find(tx, dict = dict, ignore = character(0))
  for (i in seq_along(tx)) add("find", d, tx[i], lines(fd[[i]]))
}
emit("hunspell_custom", "hunspell", list(cases))
