# stringi Unicode normalization: stri_trans_nfc, nfd, nfkc and nfkd of strings drawn from a pool of composed, combining, ligature, compatibility and Hangul scalars.
#   args: (n, cp[n], form 0 nfc 1 nfd 2 nfkc 3 nfkd, what 0 length 1 weighted code-point sum)
suppressMessages(library(stringi))
cases <- list()
pool <- c(0x41, 0x61, 0x30A, 0xC5, 0x212B, 0xE9, 0x65, 0x301, 0x323, 0x1E9B, 0xFB01, 0xBE, 0x2460, 0xAC01, 0x1100, 0x1161, 0x11A8, 0xD55C, 0x1EA0, 0x1EA4, 0x0308, 0x0344, 0x2126, 0x3A9, 0x1F80, 0xFF21, 0x20)
set.seed(20271101)
for (rep in 1:60) {
  n <- sample(2:12, 1); cp <- sample(pool, n, TRUE)
  s <- intToUtf8(cp)
  fs <- c(stri_trans_nfc(s), stri_trans_nfd(s), stri_trans_nfkc(s), stri_trans_nfkd(s))
  for (f in 0:3) {
    u <- utf8ToInt(fs[f + 1])
    cases[[length(cases) + 1]] <- case("norm", c(n, cp, f, 0), length(u), rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("norm", c(n, cp, f, 1), sum(u * seq_along(u)), rel = 0, abs = 0)
  }
}
emit("stringi", "stringi", list(cases))
