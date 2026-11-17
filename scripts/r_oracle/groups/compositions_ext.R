# compositions beyond the Aitchison geometry: rcomp, bases and balances, zeroreplace, the normal location tests, Gauss.test and the energy test of normality.
# Every result is a vector compared through three numbers q: 0 sum, 1 position-weighted sum, 2 sum of squares (row-major flattening); scalars use q = 0.
#   "rc"    (kind, n, d, p, q, x[n d] row-major, y[n d]); kind 0 cdt 1 norm 2 minus 3 times p 4 mean 5 var 6 dist (lower triangle by columns) 7 idt
#   "base"  (kind, d, nc, q, ...); kind 0 buildilrBase of the signary W[d nc] row-major; kind 1 ilrBase(D = d, "balanced"); kind 2 balanceBase column j from pos[d], neg[d]
#           (args: pos, neg); kind 3 ilr(X, V) with V[d nc] row-major then X (n = rows of the data; args: n, V, X)
#   "zr"    (n, d, a, q, x[n d], dl[d])
#   "nl"    (kind, nrep, seed, d, G, q, sizes[G], x[n d]); kind 0 one sample 1 equal variances 2 different variances; q 0 statistic 1 df 2 p value
#   "gauss" (alt, mu, sd, n, q, x[n]); q 0 statistic 1 p value
#   "etest" (nrep, seed, n, d, q, x[n d]); q 0 statistic 1 p value (R > 0 only)
suppressMessages({ library(compositions); library(energy) })
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
flat <- function(m) as.vector(t(unclass(m)))
sums <- function(fn, a, qpos, v) { v <- as.numeric(v); w <- seq_along(v); for (q in 0:2) { a2 <- a; a2[qpos] <- q; add(fn, a2, c(sum(v), sum(w * v), sum(v^2))[q + 1]) } }
set.seed(20261204)
for (rep in 1:12) {
  d <- c(3, 4, 5)[(rep - 1) %% 3 + 1]; n <- sample(8:25, 1)
  X <- matrix(rgamma(n * d, 2) + 0.05, n, d); Y <- matrix(rgamma(n * d, 3) + 0.05, n, d); p <- c(0.5, -2, 3)[rep %% 3 + 1]
  rc <- rcomp(X); rb <- rcomp(Y)
  res <- list(unclass(cdt(rc)), as.numeric(norm(rc)), unclass(rc - rb), unclass(rc * p), as.numeric(unclass(mean(rc))), var(rc), as.numeric(dist(rc)), unclass(idt(rc)))
  for (kind in 0:7) sums("rc", c(kind, n, d, p, 0, flat(X), flat(Y)), 5, flat(res[[kind + 1]]))
}
for (rep in 1:6) {
  d <- sample(3:7, 1); nc <- d - 1
  # build a valid signary: split parts successively
  W <- matrix(0, d, nc); groups <- list(1:d)
  for (j in 1:nc) {
    gi <- which(sapply(groups, length) > 1)[1]; g <- groups[[gi]]; k <- sample(1:(length(g) - 1), 1); sh <- sample(g)
    a <- sh[1:k]; b <- sh[(k + 1):length(g)]; W[a, j] <- 1; W[b, j] <- -1
    groups[[gi]] <- NULL; groups <- c(groups, list(a), list(b))
  }
  Vb <- compositions:::gsi.buildilrBase(W)
  sums("base", c(0, d, nc, 0, flat(W)), 4, flat(Vb))
  X <- matrix(rgamma(15 * d, 2) + 0.05, 15, d)
  sums("base", c(3, d, nc, 0, 15, flat(Vb), flat(X)), 4, flat(unclass(ilr(acomp(X), Vb))))
  j <- sample(1:nc, 1); pos <- as.numeric(W[, j] == 1); neg <- as.numeric(W[, j] == -1)
  # balanceBase column for the two parts, via the package's own formula on named columns
  nm <- LETTERS[1:d]; ex <- as.formula(paste("~", paste0("(", paste(nm[pos == 1], collapse = "/"), ")"), "/", paste0("(", paste(nm[neg == 1], collapse = "/"), ")")))
  Xn <- X; colnames(Xn) <- nm
  bb <- tryCatch(balanceBase(acomp(Xn), ex), error = function(e) NULL)
  if (!is.null(bb)) { bcol <- bb[, 1]; sums("base", c(2, d, nc, 0, pos, neg), 4, as.numeric(bcol)) }
}
for (d in 3:8) sums("base", c(1, d, d - 1, 0), 4, flat(ilrBase(D = d, method = "balanced")))
for (rep in 1:4) {
  d <- sample(3:5, 1); n <- sample(6:12, 1); X <- matrix(rgamma(n * d, 2), n, d); X[sample(n * d, 4)] <- 0; dl <- round(runif(d, 0.05, 0.3), 3); a <- c(2 / 3, 0.5)[rep %% 2 + 1]
  Z <- tryCatch(zeroreplace(X, d = dl, a = a), error = function(e) NULL); if (is.null(Z)) next
  sums("zr", c(n, d, a, 0, flat(X), dl), 4, flat(unclass(Z)))
}
for (rep in 1:14) {
  kind <- (rep - 1) %% 3; d <- sample(3:4, 1); G <- if (kind == 0) 1 else sample(2:3, 1); sizes <- if (kind == 0) sample(15:30, 1) else sample(12:22, G, TRUE); n <- sum(sizes)
  shift <- if (kind == 0) 0 else rep(0:(G - 1), sizes) * 0.3
  X <- matrix(rgamma(n * d, 2) + 0.2, n, d); X[, 1] <- X[, 1] * exp(shift); nrep <- c(0, 0, 99, 49)[rep %% 4 + 1]; seed <- sample(1:1e6, 1)
  set.seed(seed)
  g <- factor(rep(seq_len(G), sizes))
  r <- tryCatch(suppressWarnings(switch(kind + 1, acompNormalLocation.test(acomp(X), R = nrep), acompNormalLocation.test(acomp(X), g = g, var.equal = TRUE, R = nrep),
          acompNormalLocation.test(acomp(X), g = g, var.equal = FALSE, R = nrep))), error = function(e) NULL)
  if (is.null(r)) next
  vals <- c(unname(r$statistic), unname(r$parameter), unname(r$p.value))
  for (q in 0:2) add("nl", c(kind, nrep, seed, d, G, q, sizes, flat(X)), vals[q + 1], rel = 1e-8, abs = 1e-10)
}
for (rep in 1:5) {
  n <- sample(5:30, 1); x <- rnorm(n, 0.3, 1.2); alt <- rep %% 3; mu <- c(0, 0.2, -0.1)[rep %% 3 + 1]; sdv <- c(1, 1.3)[rep %% 2 + 1]
  r <- Gauss.test(x, mean = mu, sd = sdv, alternative = c("two.sided", "less", "greater")[alt + 1])
  add("gauss", c(alt, mu, sdv, n, 0, x), unname(r$statistic)); add("gauss", c(alt, mu, sdv, n, 1, x), unname(r$p.value), rel = 1e-8)
}
for (rep in 1:8) {
  d <- c(3, 4, 2)[(rep - 1) %% 3 + 1]; n <- sample(10:30, 1); X <- matrix(rgamma(n * d, 2) + 0.1, n, d); nrep <- c(0, 49, 99)[rep %% 3 + 1]; seed <- sample(1:1e6, 1)
  set.seed(seed)
  r <- tryCatch(suppressWarnings(if (nrep > 0) acompNormalGOF.test(acomp(X), R = nrep) else acompNormalGOF.test(acomp(X))), error = function(e) NULL)
  if (is.null(r)) next
  add("etest", c(nrep, seed, n, d, 0, flat(X)), unname(r$statistic), rel = 1e-8)
  if (nrep > 0) add("etest", c(nrep, seed, n, d, 1, flat(X)), unname(r$p.value), rel = 1e-8)
}
emit("compositions_ext", c("compositions", "energy", "gsl"), list(cases))
