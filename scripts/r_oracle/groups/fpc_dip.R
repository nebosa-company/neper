# fpc: unimodal.ind, dipp.tantrum, diptest.multi and mergenormals(method = "dipuni" / "diptantrum") under set.seed.
#   "ui": (y[..]) -> unimodal.ind(y)
#   "dt": (seed, M, what, x[..]) -> dipp.tantrum(x, dip(x), M): what 0 p.value, 1 bw
#   "dt2": (seed, M, n1, which, x1[n1], x2) -> which 0 the p value of the second dipp.tantrum call, 1 of the first plus 7
#   "dm": (seed, n, p, lab[n], x n by p row-major) -> diptest.multi(x, lab)
#   "mnd": (seed, n, d, k, cutoff, by, stat, probs[k], mu k by d row-major, Sigma k blocks of d by d row-major, z n by k row-major, x n by d row-major, cl[n]): mergenormals
#         stat 0 length(valuemerged) 1 sum(valuemerged * position) 2 sum(mergedtonumbers * position) 3 length(clusternumbers) 4 sum(clustering * position)
#         5 + i valuemerged[i + 1]
suppressMessages(library(fpc)); suppressMessages(library(diptest))
cases <- list()
set.seed(20269989)
flat <- function(m) as.vector(t(unclass(as.matrix(m))))
add <- function(nm, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = rel, abs = abs)
for (rep in 1:30) {
  ly <- sample(5:40, 1); y <- if (rep %% 3 == 0) cumsum(rnorm(ly)) else if (rep %% 3 == 1) dnorm(seq(-3, 3, length.out = ly)) + c(0, rnorm(ly - 1, sd = 0.001)) else sort(rnorm(ly), decreasing = rep %% 2 == 0)
  add("ui", y, unimodal.ind(y), 0, 0)
}
for (rep in 1:10) {
  n <- sample(30:70, 1); x <- round(c(rnorm(n %/% 2), rnorm(n - n %/% 2, mean = c(0, 2, 4)[rep %% 3 + 1])), 4); seed <- sample(1:100000, 1); M <- c(20, 50)[rep %% 2 + 1]
  set.seed(seed); r <- dipp.tantrum(x, dip(x), M = M)
  add("dt", c(seed, M, 0, x), r$p.value, 0, 0)
  add("dt", c(seed, M, 1, x), r$bw, 1e-9)
}
for (rep in 1:10) {
  n <- sample(30:70, 1); x <- round(c(rnorm(n %/% 2), rnorm(n - n %/% 2, mean = 2)), 4); x2 <- round(c(rnorm(n %/% 3), rnorm(n - n %/% 3, mean = 3)), 4); seed <- sample(1:100000, 1)
  set.seed(seed); r1 <- dipp.tantrum(x, dip(x), M = 20); r2 <- dipp.tantrum(x2, dip(x2), M = 20)
  add("dt2", c(seed, 20, length(x), 0, x, x2), r2$p.value, 0, 0)
  add("dt2", c(seed, 20, length(x), 1, x, x2), r1$p.value + 7, 0, 0)
}
for (rep in 1:10) {
  p <- sample(1:3, 1); n <- sample(30:60, 1); lab <- sample(rep(c(2, 5), length.out = n)); x <- round(matrix(rnorm(n * p), n, p) + outer(lab == 5, rep(1.5, p)), 4); seed <- sample(1:100000, 1)
  if (p == 1) x <- x[, 1, drop = FALSE]
  set.seed(seed); r <- diptest.multi(if (p == 1) x[, 1] else x, lab, M = 100)
  add("dm", c(seed, n, p, lab, flat(x)), r, 1e-9, 1e-11)
}
rs <- function(d, sc = 1) { A <- matrix(rnorm(d * d), d, d); (crossprod(A) + diag(d) * 0.3) * sc }
for (meth in c("dipuni", "diptantrum")) {
  made <- 0; rep <- 0
  while (made < 8 && rep < 100) {
    rep <- rep + 1
    d <- sample(1:2, 1); k <- sample(3:4, 1); n <- sample(60:90, 1); sep <- c(1.2, 2.5)[rep %% 2 + 1]
    mu <- matrix(rnorm(k * d) * sep, d, k); Sg <- array(0, c(d, d, k)); for (i in 1:k) Sg[, , i] <- rs(d, 0.4)
    pr <- runif(k); pr <- pr / sum(pr)
    comp <- sample(k, n, TRUE, prob = pr); x <- matrix(0, n, d); for (i in 1:n) x[i, ] <- mu[, comp[i]] + t(chol(Sg[, , comp[i]])) %*% rnorm(d)
    x <- round(x, 4)
    z <- matrix(0, n, k); for (j in 1:k) z[, j] <- pr[j] * apply(x, 1, function(r) exp(-0.5 * mahalanobis(r, mu[, j], matrix(Sg[, , j], d, d))) / sqrt(det(matrix(Sg[, , j], d, d))))
    z <- z / rowSums(z); cl <- apply(z, 1, which.max)
    if (length(unique(cl)) < k) next
    cutoff <- c(0.05, 0.2)[rep %% 3 %% 2 + 1]; by <- 0.01; seed <- sample(1:100000, 1)
    set.seed(seed)
    r <- tryCatch(suppressWarnings(mergenormals(x, clustering = cl, probs = pr, muarray = mu, Sigmaarray = Sg, z = z, method = meth, cutoff = cutoff, by = by)), error = function(e) stop("mergenormals failed in R: ", conditionMessage(e)))
    if (is.null(r)) next
    made <- made + 1
    a <- c(seed, n, d, k, cutoff, by)
    b <- c(pr, flat(t(mu)), as.vector(aperm(Sg, c(2, 1, 3))), as.vector(t(z)), as.vector(t(x)), cl)
    v <- c(length(r$valuemerged), sum(r$valuemerged * seq_along(r$valuemerged)), sum(r$mergedtonumbers * seq_along(r$mergedtonumbers)), length(r$clusternumbers), sum(r$clustering * seq_along(r$clustering)))
    for (j in 0:4) add(if (meth == "dipuni") "mnd" else "mnt", c(a, j, b), v[j + 1], 1e-9)
    rdg <- ridgeline.diagnosis(pr, mu, Sg, k = k, compute.ratio = TRUE, by = by, ridgelineplot = "none")$ratiomatrix
    add(if (meth == "dipuni") "mnd" else "mnt", c(a, 100, b), sum(upper.tri(rdg) & rdg == 1), 0, 0)
    for (j in seq_along(r$valuemerged)) add(if (meth == "dipuni") "mnd" else "mnt", c(a, 4 + j, b), r$valuemerged[j], 1e-9)
  }
}
emit("fpc_dip", c("fpc", "diptest"), list(cases))
