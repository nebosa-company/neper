# tm DocumentTermMatrix / TermDocumentMatrix from text (termFreq options), weightBin, and tidytext unnest_tokens for sentences and regex.
#   "dtm*": args (lowercase, wordLengths lower, upper, local bounds lower, upper, then four op codes in application order (0 none, 1 removePunctuation,
#           2 removeNumbers, 3 stopwords, 4 stemming), then the documents' bytes with 1 between documents).
#     answers: dnt number of terms, dtot sum of counts, dhash sum over (doc, term) of count * doc number * sum(position * code of the term),
#              dpos / dtpos position-weighted sum of the DTM (docs x terms) / TDM (terms x docs) and dbin of weightBin(DTM): only drawn when tm's locale sort of the terms is the byte order
#   "sn"/"ss": the text's codes; the unnest_tokens(token = "sentences") tokens joined by byte 1 as length and position-weighted sum
#   "rn"/"rs": args (pattern index, the text's codes); unnest_tokens(token = "regex", pattern) likewise
suppressMessages({library(tm); library(tidytext); library(dplyr)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
ws <- function(x) sum(as.vector(t(x)) * seq_len(length(x)))
set.seed(20262601)
pool <- c("The", "cat", "Dogs", "running", "analysis", "analyses", "CATS", "happily", "connected", "connection", "Hello,", "world!", "foo-bar", "3.5", "It's", "don't", "a", "an", "of", "and",
          "statistics", "42", "x1y", "ab_cd", "(parenthesis)", "well-known", "'quoted'", "TEXT", "mining", "texts", "mined", "generalization", "hopefully", "is", "was", "you're", "very",
          "Beautiful", "beautifully", "caresses", "ponies", "ties", "dying", "agreed", "sky", "cry", "the", "cat", "cat", "text", "text", "of")
nm <- c("removePunctuation", "removeNumbers", "stopwords", "stemming")
for (rep in 1:90) {
  nd <- sample(2:6, 1)
  docs <- vapply(seq_len(nd), function(i) paste(sample(pool, sample(0:14, 1), TRUE), collapse = sample(c(" ", " ", "\t", "\n"), 1)), "")
  if (rep %% 3 == 0) docs <- gsub("[^ a-zA-Z]", "", docs)
  lc <- sample(c(TRUE, TRUE, FALSE), 1); lo <- sample(1:4, 1); hi <- sample(c(Inf, 8), 1); bl <- sample(c(1, 2), 1); bh <- sample(c(Inf, 3), 1)
  ops <- sample(1:4, 4); if (rep %% 2 == 0) ops <- 1:4
  ops <- ops[seq_len(sample(1:4, 1))]
  ctl <- list(tolower = lc, wordLengths = c(lo, hi), bounds = list(local = c(bl, bh)))
  for (o in ops) ctl[[nm[o]]] <- TRUE
  ops4 <- c(ops, rep(0, 4 - length(ops)))
  corp <- VCorpus(VectorSource(docs))
  dtm <- DocumentTermMatrix(corp, control = ctl)
  if (ncol(dtm) < 1) next
  m <- as.matrix(dtm); tm_ <- as.matrix(TermDocumentMatrix(corp, control = ctl)); trm <- colnames(m)
  txt <- utf8ToInt(paste(docs, collapse = "\001"))
  a0 <- c(as.numeric(lc), lo, if (is.finite(hi)) hi else 1e9, bl, if (is.finite(bh)) bh else 1e9, ops4, txt)
  add("dnt", a0, ncol(m)); add("dtot", a0, sum(m))
  hs <- vapply(trm, function(t) { cc <- utf8ToInt(t); sum(cc * seq_along(cc)) }, 0)
  hv <- sum(as.vector(seq_len(nrow(m)) %*% m) * hs)
  add("dhash", a0, hv)
  if (identical(trm, sort(trm, method = "radix"))) {
    add("dpos", a0, ws(m)); add("dtpos", a0, ws(tm_))
    wb <- as.matrix(DocumentTermMatrix(corp, control = c(ctl, list(weighting = weightBin)))); add("dbin", a0, ws(wb))
  }
}
cat("dtm cases", length(cases), "\n")
frag <- c("Hello", "world", "the", "Mr", "U.S", "e.g", "3.5", "10", "a", "B", "cat", "x_y", "...", ".", ".", "!", "?", "?!", ",", ";", ":", "-", "\"", "'", "(", ")", "[", "]", " ", " ", " ", "\t", "\n", "It's", "etc")
for (rep in 1:200) {
  txt <- paste(sample(frag, sample(2:30, 1), TRUE), collapse = sample(c(" ", "", " "), 1))
  if (nchar(trimws(txt)) == 0) next
  r <- (tibble(text = txt) %>% unnest_tokens(o, text, token = "sentences"))$o
  s <- if (length(r)) paste(r, collapse = "\001") else ""; cc <- utf8ToInt(s); if (!length(cc)) cc <- integer(0)
  add("sn", utf8ToInt(txt), length(cc)); add("ss", utf8ToInt(txt), sum(cc * seq_along(cc)))
}
cat("sent cases", length(cases), "\n")
pats <- c("\\s+", ",", "[,;]\\s*", "\\W+", "[^a-z]+", "\\s*[.!?]\\s*", "a|bb", "[0-9]+")
rf <- c("Hello", "world", "the", "A", "bb", "a", "x_y", "3", "10", ",", ";", ".", "!", " ", " ", "\t", "\n", "-", "'", "cat", "B")
for (rep in 1:160) {
  txt <- paste(sample(rf, sample(2:25, 1), TRUE), collapse = sample(c(" ", "", ","), 1)); pi <- 1 + rep %% length(pats)
  if (nchar(txt) == 0) next
  r <- (tibble(text = txt) %>% unnest_tokens(o, text, token = "regex", pattern = pats[pi]))$o
  s <- if (length(r)) paste(r, collapse = "\001") else ""; cc <- utf8ToInt(s); if (!length(cc)) cc <- integer(0)
  add("rn", c(pi - 1, utf8ToInt(txt)), length(cc)); add("rs", c(pi - 1, utf8ToInt(txt)), sum(cc * seq_along(cc)))
}
emit("tm_dtm", c("tm", "tidytext", "dplyr", "tibble", "SnowballC"), list(cases))
