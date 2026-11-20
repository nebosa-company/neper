# topicmodels CTM (VEM). Args: fit config, quantity, i, j (see main.e); the corpus is a fixed formula in both languages.
suppressMessages({ library(topicmodels); library(slam) })
dtm_of <- function(nd, nv, salt) {
  m <- matrix(0, nd, nv)
  for (i in 1:nd) for (j in 1:nv) {
    v <- (i * j + 3 * i + 5 * j + salt) %% 7
    if (i %% 2 == 0 && j <= nv %/% 2) v <- v + 3
    if (i %% 2 == 1 && j > nv %/% 2) v <- v + 2
    m[i, j] <- v
  }
  dimnames(m) <- list(paste0("d", 1:nd), paste0("t", 1:nv))
  m
}
m1 <- dtm_of(12, 15, 0); m2 <- dtm_of(6, 15, 3)
x1 <- as.simple_triplet_matrix(m1); x2 <- as.simple_triplet_matrix(m2)
cases <- list()
# the long fits pass a gradient-norm test in the conjugate gradient whose branch rounding can flip, so their converged values agree to ~1e-7 absolute (one EM step agrees to 1e-13); the new-data fit inherits the first fit
loose <- rep(1e-6, 5)
add <- function(cfg, what, i, j, val, rel = loose[cfg]) cases[[length(cases) + 1]] <<- case("vem", c(cfg, what, i, j), val, rel = rel, abs = if (rel > 0 && loose[cfg] > 1e-8) 1e-6 else 1e-12)
dump <- function(cfg, fit, nt = 3, nr = 2) {
  K <- fit@k; D <- fit@Dim[1]; V <- fit@Dim[2]
  for (a in 1:K) for (b in 1:V) add(cfg, 1, a, b, fit@beta[a, b])
  for (a in 1:D) for (b in 1:K) add(cfg, 2, a, b, fit@gamma[a, b])
  for (a in 1:(K - 1)) add(cfg, 3, a, 0, fit@mu[a])
  for (a in 1:(K - 1)) for (b in 1:(K - 1)) add(cfg, 4, a, b, fit@Sigma[a, b])
  for (a in 1:D) for (b in 1:(K - 1)) add(cfg, 5, a, b, fit@nusquared[a, b])
  for (a in 1:D) add(cfg, 6, a, 0, fit@loglikelihood[a])
  add(cfg, 7, 0, 0, fit@iter, rel = 0)
  ll <- logLik(fit); add(cfg, 8, 0, 0, as.numeric(ll)); add(cfg, 9, 0, 0, attr(ll, "df"), rel = 0)
  add(cfg, 10, 0, 0, perplexity(fit))
  wv <- fit@wordassignments$v; for (a in seq_along(wv)) add(cfg, 11, a, 0, wv[a], rel = 0)
  if (length(fit@logLiks)) for (a in seq_along(fit@logLiks)) add(cfg, 12, a, 0, fit@logLiks[a])
  tt <- terms(fit, nt); for (a in 1:K) for (b in 1:nt) add(cfg, 13, a, b, as.integer(sub("t", "", tt[b, a])), rel = 0)
  tp <- topics(fit, nr); for (a in 1:D) for (b in 1:nr) add(cfg, 14, a, b, as.integer(tp[b, a]), rel = 0)
  po <- posterior(fit); for (a in 1:K) for (b in 1:V) add(cfg, 15, a, b, po$terms[a, b])
}
f1 <- CTM(x1, 3, method = "VEM", control = list(seed = 100)); dump(1, f1)
f2 <- CTM(x1, 4, method = "VEM", control = list(seed = 7)); dump(2, f2, 4, 3)
f3 <- CTM(x1, 3, method = "VEM", control = list(seed = 11, initialize = "seeded")); dump(3, f3)
f4 <- CTM(x1, 2, method = "VEM", control = list(seed = 5, var = list(iter.max = 20), em = list(iter.max = 15), keep = 1)); dump(4, f4, 2, 2)
po <- posterior(f1, x2); for (a in 1:6) for (b in 1:3) add(5, 2, a, b, po$topics[a, b])
add(5, 10, 0, 0, perplexity(f1, x2))
emit("topicmodels_ctm", "topicmodels", list(cases))
