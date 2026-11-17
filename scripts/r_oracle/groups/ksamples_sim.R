# ksamples_sim: the exact and simulated p-values, the null distributions (dist = TRUE), qn.test with normal scores,
# contingency2xt and the combined tests. A simulated value is compared exactly: the stream is seeded right before the call.
#   "ads"  (method 1 sim 2 exact, seed, Nsim, part, idx, k, sizes..., data...)  ad.test
#          part 0 sim/exact p v1, 1 p v2, 2 null.dist1[idx], 3 null.dist2[idx], 4 length(null.dist1), 5 sig
#   "qns"  (method, test 0 KW 1 vdW 2 NS, seed, Nsim, part, idx, k, sizes..., data...)  qn.test
#          part 0 statistic, 1 asymptotic p, 2 p, 3 null.dist[idx], 4 length(null.dist), 5 n.ties
#   "c2s"  (method, seed, Nsim, part, idx, tab0, t, A..., B...)  contingency2xt
#          part 0 KW, 1 asymptotic p, 2 p, 3 null.dist value idx, 4 prob idx, 5 length of the table or vector
#   "adc"  (method, seed, Nsim, part, idx, M, k per set..., sizes..., data...)  ad.test.combined
#          part 0 AD v1, 1 T v1, 2 asymptotic p v1, 3 sim/exact p v1, 4..7 the same for v2, 8 sig.c, 9 mu.c, 10 null.dist1[idx], 11 its length
#   "qnc"  (method, test, seed, Nsim, part, idx, M, k per set..., sizes..., data...)  qn.test.combined
#          part 0 statistic, 1 asymptotic p, 2 p, 3 null.dist[idx], 4 length
#   "c2c"  (method, seed, Nsim, part, idx, M, t per set..., A and B per set...)  contingency2xt.comb
#          part 0 KW, 1 asymptotic p, 2 p, 3 value idx, 4 prob idx, 5 length
#   "nsc"  (n, i)  SuppDists normOrder(n)[i]
suppressMessages(library(kSamples))
cases <- list()
add <- function(fn, args, want, rel = 1e-12, abs = 1e-14) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
smp <- function(m, ties) { v <- rnorm(m, runif(1, -0.5, 0.5), runif(1, 0.8, 1.5)); if (ties) round(v, 0) else round(v, 5) }
sets <- function(k, n, ties) lapply(n, function(m) smp(m, ties))
meth <- c("asymptotic", "simulated", "exact")
nc <- function(n) { np <- sum(n); r <- 1; for (i in 1:(length(n) - 1)) { r <- r * choose(np, n[i]); np <- np - n[i] }; r }
pickidx <- function(len, m) sort(unique(sample(len, min(m, len))))

# normal scores
for (n in c(2, 3, 4, 5, 7, 10, 15, 21, 30, 41, 60)) { v <- SuppDists::normOrder(n); for (i in unique(c(1, ceiling(n / 2), n))) add("nsc", c(n, i), v[i]) }

# ad.test
for (rep in 1:36) {
  k <- sample(2:4, 1); n <- sample(3:8, k, TRUE); ties <- rep %% 3 == 0
  if (nc(n) > 4000 && rep %% 2 == 0) n <- pmin(n, 5)
  lst <- sets(k, n, ties); m <- if (rep %% 2 == 1) 1 else 2
  if (m == 2 && nc(n) > 4000) m <- 1
  nsim <- sample(c(150, 250, 400), 1); seed <- sample(1:100000, 1); dist <- rep %% 3 != 1
  set.seed(seed)
  r <- do.call(ad.test, c(lst, list(method = meth[m + 1], Nsim = nsim, dist = dist)))
  base <- c(m, seed, nsim)
  tail <- c(k, n, unlist(lst))
  add("ads", c(base, 0, 0, tail), r$ad[1, 4]); add("ads", c(base, 1, 0, tail), r$ad[2, 4]); add("ads", c(base, 5, 0, tail), r$sig)
  if (dist) {
    add("ads", c(base, 4, 0, tail), length(r$null.dist1))
    for (i in pickidx(length(r$null.dist1), 6)) { add("ads", c(base, 2, i, tail), r$null.dist1[i]); add("ads", c(base, 3, i, tail), r$null.dist2[i]) }
  }
}

# qn.test
for (rep in 1:48) {
  k <- sample(2:4, 1); n <- sample(3:8, k, TRUE); ties <- rep %% 3 == 0
  if (nc(n) > 4000) n <- pmin(n, 5)
  lst <- sets(k, n, ties); tt <- (rep - 1) %% 3; m <- if (rep %% 2 == 1) 1 else 2
  if (m == 2 && nc(n) > 4000) m <- 1
  nsim <- sample(c(150, 250, 400), 1); seed <- sample(1:100000, 1); dist <- rep %% 3 != 1
  set.seed(seed)
  r <- do.call(qn.test, c(lst, list(test = c("KW", "vdW", "NS")[tt + 1], method = meth[m + 1], Nsim = nsim, dist = dist)))
  base <- c(m, tt, seed, nsim); tail <- c(k, n, unlist(lst))
  add("qns", c(base, 0, 0, tail), r$qn[[1]]); add("qns", c(base, 1, 0, tail), r$qn[[2]]); add("qns", c(base, 2, 0, tail), r$qn[[3]]); add("qns", c(base, 5, 0, tail), r$n.ties)
  if (dist) {
    add("qns", c(base, 4, 0, tail), length(r$null.dist))
    for (i in pickidx(length(r$null.dist), 8)) add("qns", c(base, 3, i, tail), r$null.dist[i])
  }
}

# contingency2xt
for (rep in 1:40) {
  tn <- sample(2:5, 1); A <- sample(0:6, tn, TRUE); B <- sample(1:6, tn, TRUE)
  m <- if (rep %% 2 == 1) 1 else 2; nsim <- sample(c(120, 300, 500), 1); seed <- sample(1:100000, 1); dist <- rep %% 3 != 1; tab0 <- rep %% 4 < 2
  if (m == 2 && choose(sum(A) + tn - 1, tn - 1) > 4000) m <- 1
  set.seed(seed)
  r <- contingency2xt(A, B, method = meth[m + 1], dist = dist, tab0 = tab0, Nsim = if (m == 2) 1e6 else nsim)
  base <- c(m, seed, if (m == 2) 1e6 else nsim); tail <- c(tab0, tn, A, B)
  add("c2s", c(base, 0, 0, tail), r$KW.cont[[1]]); add("c2s", c(base, 1, 0, tail), r$KW.cont[[2]]); add("c2s", c(base, 2, 0, tail), r$KW.cont[[3]])
  if (dist) {
    nd <- r$null.dist
    if (is.matrix(nd)) {
      add("c2s", c(base, 5, 0, tail), nrow(nd))
      for (i in pickidx(nrow(nd), 6)) { add("c2s", c(base, 3, i, tail), nd[i, 1]); add("c2s", c(base, 4, i, tail), nd[i, 2]) }
    } else {
      add("c2s", c(base, 5, 0, tail), length(nd))
      for (i in pickidx(length(nd), 6)) add("c2s", c(base, 3, i, tail), nd[i])
    }
  }
}

# the combined tests
for (rep in 1:24) {
  M <- sample(2:3, 1); ks <- sample(2:3, M, TRUE); ns <- lapply(ks, function(k) sample(3:6, k, TRUE)); ties <- rep %% 3 == 0
  ds <- lapply(1:M, function(i) sets(ks[i], ns[[i]], ties))
  ncomb <- prod(sapply(ns, nc)); m <- if (rep %% 2 == 1) 1 else 2; if (m == 2 && ncomb > 3000) m <- 1
  nsim <- if (m == 2) 10000 else sample(c(120, 250), 1); seed <- sample(1:100000, 1); dist <- rep %% 3 != 0
  tail <- c(M, ks, unlist(ns), unlist(ds))
  set.seed(seed)
  r <- do.call(ad.test.combined, c(ds, list(method = meth[m + 1], Nsim = nsim, dist = dist)))
  base <- c(m, seed, nsim)
  for (p in 0:3) { add("adc", c(base, p, 0, tail), r$ad.c[1, p + 1]); add("adc", c(base, 4 + p, 0, tail), r$ad.c[2, p + 1]) }
  add("adc", c(base, 8, 0, tail), r$sig.c); add("adc", c(base, 9, 0, tail), r$mu.c)
  if (dist) { add("adc", c(base, 11, 0, tail), length(r$null.dist1)); for (i in pickidx(length(r$null.dist1), 5)) add("adc", c(base, 10, i, tail), r$null.dist1[i]) }
  tt <- (rep - 1) %% 3
  set.seed(seed)
  q <- do.call(qn.test.combined, c(ds, list(test = c("KW", "vdW", "NS")[tt + 1], method = meth[m + 1], Nsim = nsim, dist = dist)))
  qb <- c(m, tt, seed, nsim)
  for (p in 0:2) add("qnc", c(qb, p, 0, M, ks, unlist(ns), unlist(ds)), q$qn.c[[p + 1]])
  if (dist) { add("qnc", c(qb, 4, 0, M, ks, unlist(ns), unlist(ds)), length(q$null.dist)); for (i in pickidx(length(q$null.dist), 5)) add("qnc", c(qb, 3, i, M, ks, unlist(ns), unlist(ds)), q$null.dist[i]) }
}
for (rep in 1:20) {
  M <- sample(2:3, 1); tv <- sample(2:4, M, TRUE)
  dl <- lapply(tv, function(tn) list(sample(0:4, tn, TRUE), sample(1:4, tn, TRUE)))
  ncomb <- prod(sapply(dl, function(d) choose(sum(d[[1]]) + length(d[[1]]) - 1, length(d[[1]]) - 1)))
  m <- if (rep %% 2 == 1) 1 else 2; if (m == 2 && ncomb > 4000) m <- 1
  nsim <- if (m == 2) 10000 else sample(c(150, 300), 1); seed <- sample(1:100000, 1); dist <- rep %% 3 != 0
  set.seed(seed)
  r <- contingency2xt.comb(dl, method = meth[m + 1], dist = dist, Nsim = nsim)
  base <- c(m, seed, nsim); tail <- c(M, tv, unlist(dl))
  for (p in 0:2) add("c2c", c(base, p, 0, tail), r$kw.c[[p + 1]])
  if (dist) {
    nd <- r$null.dist
    add("c2c", c(base, 5, 0, tail), nrow(nd))
    for (i in pickidx(nrow(nd), 5)) { add("c2c", c(base, 3, i, tail), nd[i, 1]); add("c2c", c(base, 4, i, tail), nd[i, 2]) }
  }
}
emit("ksamples_sim", c("kSamples", "SuppDists"), list(cases))
