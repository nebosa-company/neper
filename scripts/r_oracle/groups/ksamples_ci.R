# ksamples_ci: SteelConfInt, the many-to-one confidence bounds (asymptotic through R's integrate and uniroot, exact and simulated through the
# permutation matrix). A simulated value is compared exactly: the stream is seeded right before the call.
#   "sci"  (alt 0 less 1 greater 2 two.sided, conf.level, method 0 asymptotic 1 simulated 2 exact, seed, Nsim, part, idx, k, sizes..., data...)
#          part 0 level of the conservative asymptotic bounds, 1 level of the closest ones, 2 L[idx], 3 U[idx], 4 Lc[idx], 5 Uc[idx],
#          6 i.L[idx], 7 i.U[idx], 8 i.Lc[idx], 9 i.Uc[idx], 10 level conservative sim/exact, 11 level closest, 12 LX, 13 UX, 14 LXc, 15 UXc,
#          16..19 i.L, i.U, i.Lc, i.Uc of the sim/exact bounds, 20 n.ties
suppressMessages(library(kSamples))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-14)
smp <- function(m, ties) { v <- rnorm(m, runif(1, -0.5, 0.5), runif(1, 0.8, 1.5)); if (ties) round(v, 0) else round(v, 5) }
meth <- c("asymptotic", "simulated", "exact")
alts <- c("less", "greater", "two.sided")
nc <- function(n) { np <- sum(n); r <- 1; for (i in 1:(length(n) - 1)) { r <- r * choose(np, n[i]); np <- np - n[i] }; r }
for (rep in 1:45) {
  k <- sample(2:4, 1); n <- sample(4:9, k, TRUE); ties <- rep %% 4 == 0
  if (nc(n) > 3000) n <- pmin(n, 5)
  lst <- lapply(n, function(m) smp(m, ties))
  m <- rep %% 3; if (m == 2 && nc(n) > 3000) m <- 1
  alt <- (rep %/% 3) %% 3; conf <- c(0.9, 0.95, 0.99)[(rep %% 3) + 1]
  nsim <- if (m == 2) 100000 else sample(c(150, 250, 400), 1); seed <- sample(1:100000, 1)
  set.seed(seed)
  r <- do.call(SteelConfInt, c(lst, list(conf.level = conf, alternative = alts[alt + 1], method = meth[m + 1], Nsim = nsim)))
  base <- c(alt, conf, m, seed, nsim); tail <- c(k, n, unlist(lst))
  A <- r$bounds[[1]]; B <- r$bounds[[2]]
  add("sci", c(base, 0, 0, tail), as.numeric(A$level[1])); add("sci", c(base, 1, 0, tail), as.numeric(B$level[1]))
  add("sci", c(base, 20, 0, tail), r$n.ties)
  for (j in 1:(k - 1)) {
    add("sci", c(base, 2, j, tail), A$L[j]); add("sci", c(base, 3, j, tail), A$U[j]); add("sci", c(base, 4, j, tail), B$L[j]); add("sci", c(base, 5, j, tail), B$U[j])
    for (q in 1:4) if (!is.na(r$i.LU[j, q])) add("sci", c(base, 5 + q, j, tail), r$i.LU[j, q])
  }
  if (m > 0) {
    AX <- r$bounds[[3]]; BX <- r$bounds[[4]]
    add("sci", c(base, 10, 0, tail), as.numeric(AX$level[1])); add("sci", c(base, 11, 0, tail), as.numeric(BX$level[1]))
    for (j in 1:(k - 1)) {
      add("sci", c(base, 12, j, tail), AX$L[j]); add("sci", c(base, 13, j, tail), AX$U[j]); add("sci", c(base, 14, j, tail), BX$L[j]); add("sci", c(base, 15, j, tail), BX$U[j])
      for (q in 1:4) if (!is.na(r$i.LUX[j, q])) add("sci", c(base, 15 + q, j, tail), r$i.LUX[j, q])
    }
  }
}
emit("ksamples_ci", "kSamples", list(cases))
