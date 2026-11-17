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
  # SMART normalisations u (pivoted unique) and b (byte size): args (nd, nt, tf, idf, norm 2 u 3 b, pivot or alpha, slope, term lengths[nt], counts)
  {
    nm_ <- vapply(sample(2:9, nt, TRUE), function(k) paste(sample(letters, k, TRUE), collapse = ""), ""); nm_ <- make.unique(nm_); mq <- m; colnames(mq) <- nm_
    dtq <- as.DocumentTermMatrix(as.simple_triplet_matrix(mq), weighting = weightTf); tf2 <- sample(0:4, 1); id2 <- sample(0:2, 1)
    piv <- runif(1, 1, 3); slp <- runif(1, 0.1, 0.9); al <- runif(1, 0.5, 1.2); ln <- nchar(nm_)
    wu <- suppressWarnings(weightSMART(dtq, paste0(tfl[tf2 + 1], idl[id2 + 1], "u"), control = list(pivot = piv, slope = slp)))
    add("smartx", c(nd, nt, tf2, id2, 2, piv, slp, ln, as.vector(t(m))), ws(as.matrix(wu)))
    wb <- suppressWarnings(weightSMART(dtq, paste0(tfl[tf2 + 1], idl[id2 + 1], "b"), control = list(alpha = al)))
    add("smartx", c(nd, nt, tf2, id2, 3, al, 0, ln, as.vector(t(m))), ws(as.matrix(wb)))
  }
  sp <- runif(1, 0.3, 0.9)
  keep <- as.numeric(seq_len(nt) %in% match(Terms(removeSparseTerms(dtm, sp)), Terms(dtm)))
  add("sparse", c(nd, nt, sp, 0, 0, as.vector(t(m))), sum(keep * seq_len(nt)))
  cs <- m %*% t(m) / sqrt(outer(rowSums(m^2), rowSums(m^2)))
  add("cosine", a0, ws(cs))
}
# findFreqTerms "freq" (nd, nt, lower, upper, 0, m) and findAssocs "assoc" (nd, nt, term index, corlimit, 0 indices / 1 values, m): answered as sum(position * index) (or value) + 1000 * count
for (rep in 1:30) {
  nd <- sample(6:14, 1); nt <- sample(5:12, 1); m <- matrix(rpois(nd * nt, 1.2), nd); dimnames(m) <- list(paste0("d", seq_len(nd)), paste0("t", seq_len(nt)))
  dtm <- as.DocumentTermMatrix(as.simple_triplet_matrix(m), weighting = weightTf); lo <- sample(2:8, 1); hi <- lo + sample(2:12, 1)
  ft <- findFreqTerms(dtm, lo, hi); ix <- match(ft, colnames(m)); add("freq", c(nd, nt, lo, hi, 0, as.vector(t(m))), sum(seq_along(ix) * ix) + 1000 * length(ix))
  tj <- sample(nt, 1); cl <- sample(c(0, 0.1, 0.3), 1); fa <- suppressWarnings(findAssocs(dtm, colnames(m)[tj], cl))[[1]]
  if (length(fa)) { ia <- match(names(fa), colnames(m)); add("assoc", c(nd, nt, tj - 1, cl, 0, as.vector(t(m))), sum(seq_along(ia) * ia) + 1000 * length(ia)); add("assoc", c(nd, nt, tj - 1, cl, 1, as.vector(t(m))), sum(seq_along(fa) * unname(fa)) + 1000 * length(fa)) }
  else { add("assoc", c(nd, nt, tj - 1, cl, 0, as.vector(t(m))), 0); add("assoc", c(nd, nt, tj - 1, cl, 1, as.vector(t(m))), 0) }
}
emit("tm", c("tm", "tidytext", "slam"), list(cases))
