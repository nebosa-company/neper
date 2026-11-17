# ksamples_steel: Steel.test, jt.test and the Jonckheere-Terpstra distribution functions. A simulated value is compared exactly: the stream is
# seeded right before the call.
#   "stl"  (alt 1 greater -1 less 0 two-sided, method 0 asymptotic 1 sim 2 exact, seed, Nsim, cc, part, idx, k, sizes..., data...)  Steel.test
#          part 0 statistic, 1 asymptotic p, 2 sim/exact p, 3 W[idx], 4 Wstand[idx], 5 pval.asympt.adj[idx], 6 pval.adj[idx], 7 null.dist[idx],
#          8 length(null.dist), 9 mu[idx], 10 tau[idx], 11 sig0, 12 sig[idx], 13 n.ties
#   "jtt"  (method, seed, Nsim, part, idx, k, sizes..., data...)  jt.test
#          part 0 statistic, 1 mu, 2 sig, 3 asymptotic p, 4 sim/exact p, 5 null.dist[idx], 6 length, 7 n.ties
#   "jtd"  (which 0 djt 1 pjt 2 qjt, x or p, k, nn...)
suppressMessages(library(kSamples))
cases <- list()
add <- function(fn, args, want, rel = 1e-12, abs = 1e-14) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
smp <- function(m, ties) { v <- rnorm(m, runif(1, -0.5, 0.5), runif(1, 0.8, 1.5)); if (ties) round(v, 0) else round(v, 5) }
meth <- c("asymptotic", "simulated", "exact")
alts <- c("less", "two-sided", "greater")
nc <- function(n) { np <- sum(n); r <- 1; for (i in 1:(length(n) - 1)) { r <- r * choose(np, n[i]); np <- np - n[i] }; r }
pickidx <- function(len, m) sort(unique(sample(len, min(m, len))))

for (rep in 1:48) {
  k <- sample(2:4, 1); n <- sample(3:8, k, TRUE); ties <- rep %% 3 == 0
  if (nc(n) > 4000) n <- pmin(n, 5)
  lst <- lapply(n, function(m) smp(m, ties))
  m <- rep %% 3; if (m == 2 && nc(n) > 4000) m <- 1
  alt <- ((rep %/% 3) %% 3) - 1; altc <- c("less", "two-sided", "greater")[alt + 2]
  cc <- rep %% 4 != 0; nsim <- sample(c(150, 250, 400), 1); seed <- sample(1:100000, 1); dist <- rep %% 2 == 0 || (alt == 0 && m > 0)
  set.seed(seed)
  r <- do.call(Steel.test, c(lst, list(method = meth[m + 1], alternative = altc, continuity.corr = cc, Nsim = nsim, dist = dist)))
  base <- c(alt, m, seed, nsim, cc); tail <- c(k, n, unlist(lst))
  add("stl", c(base, 0, 0, tail), r$st[[1]]); add("stl", c(base, 1, 0, tail), r$st[[2]])
  if (m > 0) add("stl", c(base, 2, 0, tail), r$st[[3]])
  add("stl", c(base, 13, 0, tail), r$n.ties); add("stl", c(base, 11, 0, tail), r$sig0)
  for (j in 1:(k - 1)) {
    add("stl", c(base, 3, j, tail), r$W[j]); add("stl", c(base, 4, j, tail), r$Wstand[j]); add("stl", c(base, 5, j, tail), r$pval.asympt.adj[j])
    add("stl", c(base, 9, j, tail), r$mu[j]); add("stl", c(base, 10, j, tail), r$tau[j]); add("stl", c(base, 12, j, tail), r$sig[j])
    if (m > 0 && dist) add("stl", c(base, 6, j, tail), r$pval.adj[j])
  }
  if (m > 0 && dist) {
    add("stl", c(base, 8, 0, tail), length(r$null.dist))
    for (i in pickidx(length(r$null.dist), 6)) add("stl", c(base, 7, i, tail), r$null.dist[i])
  }
}

for (rep in 1:48) {
  k <- sample(2:4, 1); n <- sample(3:8, k, TRUE); ties <- rep %% 3 == 0
  if (nc(n) > 4000) n <- pmin(n, 5)
  lst <- lapply(n, function(m) smp(m, ties))
  m <- rep %% 3; if (m == 2 && nc(n) > 4000) m <- 1
  nsim <- sample(c(150, 250, 400), 1); seed <- sample(1:100000, 1); dist <- rep %% 2 == 0
  set.seed(seed)
  r <- do.call(jt.test, c(lst, list(method = meth[m + 1], Nsim = nsim, dist = dist)))
  base <- c(m, seed, nsim); tail <- c(k, n, unlist(lst))
  for (p in 0:3) add("jtt", c(base, p, 0, tail), r$JT[[p + 1]])
  if (m > 0) add("jtt", c(base, 4, 0, tail), r$JT[[5]])
  add("jtt", c(base, 7, 0, tail), r$n.ties)
  if (m > 0 && dist) {
    add("jtt", c(base, 6, 0, tail), length(r$null.dist))
    for (i in pickidx(length(r$null.dist), 6)) add("jtt", c(base, 5, i, tail), r$null.dist[i])
  }
}

for (rep in 1:16) {
  k <- sample(2:4, 1); nn <- sample(2:7, k, TRUE); L <- sum(sort(nn)[1:(k - 1)] * rev(cumsum(rev(sort(nn))))[2:k])
  for (x in unique(c(0, L %/% 3, L %/% 2, L, L + 2, sample(0:L, 2)))) {
    add("jtd", c(0, x, k, nn), djt(x, nn)); add("jtd", c(1, x, k, nn), pjt(x, nn))
  }
  for (p in c(0, 0.01, 0.25, 0.5, 0.9, 0.975)) add("jtd", c(2, p, k, nn), qjt(p, nn))
  pp <- pjt(sample(0:L, 2), nn); for (p in pp) if (!is.na(qjt(p, nn))) add("jtd", c(2, p, k, nn), qjt(p, nn))
}
emit("ksamples_steel", "kSamples", list(cases))
