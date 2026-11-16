# tm weightings and removeSparseTerms and tidytext bind_tf_idf on a document-term count matrix (docs by terms, row-major).
#   args: (nd, nt, a, b, c, counts[nd*nt])   a b c: SMART letter indices for "smart", sparse level in a for "sparse"
#   fn "tfidf_norm", "tfidf_raw", "tidy", "smart" (weighted sum of the matrix), "sparse" (kept terms weighted by position), "cosine" (weighted sum of the similarity matrix)
suppressMessages({library(tm); library(tidytext); library(slam)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
ws <- function(x) sum(as.vector(t(x)) * seq_len(length(x)))
set.seed(20261211)
tfl <- c("n", "l", "a", "b", "L"); idl <- c("n", "t", "p"); nl <- c("n", "c")
for (rep in 1:24) {
  nd <- sample(5:12, 1); nt <- sample(6:20, 1)
  m <- matrix(rpois(nd * nt, 0.8) * (runif(nd * nt) < 0.7), nd)
  for (i in seq_len(nd)) if (sum(m[i, ]) == 0) m[i, sample(nt, 1)] <- 2
  for (j in seq_len(nt)) if (sum(m[, j]) == 0) m[sample(nd, 1), j] <- 1
  dimnames(m) <- list(paste0("d", seq_len(nd)), paste0("t", seq_len(nt)))
  dtm <- as.DocumentTermMatrix(as.simple_triplet_matrix(m), weighting = weightTf)
  a0 <- c(nd, nt, 0, 0, 0, as.vector(t(m)))
  add("tfidf_norm", a0, ws(as.matrix(weightTfIdf(dtm, normalize = TRUE))))
  add("tfidf_raw", a0, ws(as.matrix(weightTfIdf(dtm, normalize = FALSE))))
  tt <- data.frame(doc = rep(seq_len(nd), nt), term = rep(seq_len(nt), each = nd), n = as.vector(m)); tt <- tt[tt$n > 0, ]
  b <- bind_tf_idf(tt, term, doc, n); mm <- matrix(0, nd, nt); mm[cbind(b$doc, b$term)] <- b$tf_idf
  add("tidy", a0, ws(mm))
  tf <- sample(0:4, 1); idk <- sample(0:2, 1); nk <- sample(0:1, 1)
  w <- suppressWarnings(weightSMART(dtm, paste0(tfl[tf + 1], idl[idk + 1], nl[nk + 1])))
  add("smart", c(nd, nt, tf, idk, nk, as.vector(t(m))), ws(as.matrix(w)))
  sp <- runif(1, 0.3, 0.9)
  keep <- as.numeric(seq_len(nt) %in% match(Terms(removeSparseTerms(dtm, sp)), Terms(dtm)))
  add("sparse", c(nd, nt, sp, 0, 0, as.vector(t(m))), sum(keep * seq_len(nt)))
  cs <- m %*% t(m) / sqrt(outer(rowSums(m^2), rowSums(m^2)))
  add("cosine", a0, ws(cs))
}
emit("tm", c("tm", "tidytext", "slam"), list(cases))
