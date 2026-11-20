# topicmodels LDA (Gibbs) under set.seed. Args: fit config, quantity, i, j (see main.e); the corpus is a fixed formula in both languages.
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
REL <- 1e-11
add <- function(cfg, what, i, j, val, rel = REL) cases[[length(cases) + 1]] <<- case("gibbs", c(cfg, what, i, j), val, rel = rel, abs = 0)
dump <- function(cfg, fit, nt = 3, nr = 2) {
  K <- fit@k; D <- fit@Dim[1]; V <- fit@Dim[2]
  for (a in 1:K) for (b in 1:V) add(cfg, 1, a, b, fit@beta[a, b])
  for (a in 1:D) for (b in 1:K) add(cfg, 2, a, b, fit@gamma[a, b])
  add(cfg, 3, 0, 0, fit@alpha)
  ll <- logLik(fit); add(cfg, 4, 0, 0, as.numeric(ll)); add(cfg, 5, 0, 0, attr(ll, "df"), rel = 0)
  for (a in seq_along(fit@z)) add(cfg, 6, a, 0, fit@z[a], rel = 0)
  wv <- fit@wordassignments$v; for (a in seq_along(wv)) add(cfg, 7, a, 0, wv[a], rel = 0)
  if (length(fit@logLiks)) for (a in seq_along(fit@logLiks)) add(cfg, 8, a, 0, fit@logLiks[a])
  tt <- terms(fit, nt); for (a in 1:K) for (b in 1:nt) add(cfg, 11, a, b, as.integer(sub("t", "", tt[b, a])), rel = 0)
  tp <- topics(fit, nr); for (a in 1:D) for (b in 1:nr) add(cfg, 12, a, b, as.integer(tp[b, a]), rel = 0)
  po <- posterior(fit); for (a in 1:K) for (b in 1:V) add(cfg, 13, a, b, po$terms[a, b])
}
f1 <- LDA(x1, 3, method = "Gibbs", control = list(seed = 1, iter = 100)); dump(1, f1)
f2 <- LDA(x1, 4, method = "Gibbs", control = list(seed = 2, iter = 60, alpha = 0.5, delta = 0.05, keep = 10)); dump(2, f2, 4, 3)
f3 <- LDA(x1, 3, method = "Gibbs", model = f1, control = list(seed = 3, iter = 40, initialize = "beta")); dump(3, f3)
f4 <- LDA(x1, 3, method = "Gibbs", model = f1, control = list(seed = 4, iter = 30, initialize = "z")); dump(4, f4)
# new data under the first fit: the topics of the sampled theta and the three perplexities
po <- posterior(f1, x2, control = list(seed = 9, iter = 50)); for (a in 1:6) for (b in 1:3) add(5, 2, a, b, po$topics[a, b])
add(5, 14, 1, 0, perplexity(f1, x2, control = list(seed = 9, iter = 50)))
add(5, 14, 2, 0, perplexity(f1, x2, use_theta = FALSE))
add(5, 14, 3, 0, perplexity(f1, x1, estimate_theta = FALSE))
emit("topicmodels_gibbs", "topicmodels", list(cases))
