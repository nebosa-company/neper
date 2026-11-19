# fpc: bhattacharyya.dist. Args: (d, mu1[d], mu2[d], Sigma1 row-major [d * d], Sigma2 row-major [d * d])
suppressMessages(library(fpc))
cases <- list()
set.seed(20262390)
rs <- function(d) { A <- matrix(rnorm(d * d), d, d); S <- crossprod(A) + diag(d) * 0.3; S }
for (rep in 1:60) {
  d <- sample(1:4, 1); m1 <- rnorm(d); m2 <- rnorm(d); S1 <- rs(d); S2 <- rs(d)
  cases[[length(cases) + 1]] <- case("bhat", c(d, m1, m2, as.vector(t(S1)), as.vector(t(S2))), bhattacharyya.dist(m1, m2, S1, S2), rel = 1e-10, abs = 1e-12)
}
# "mnb" (n, d, k, cutoff, probs[k], mu k x d row-major, Sigma k * d * d, z n x k row-major, x n x d row-major, stat): mergenormals(method = "bhat"); stat 0 the number of values, 1 sum(values * position), 2 sum(mergedtonumbers * position), 3 the number of clusters left
for (rep in 1:7) {
  d <- sample(1:3, 1); k <- sample(3:6, 1); n <- sample(40:120, 1)
  mu <- matrix(rnorm(k * d), d, k); Sg <- array(0, c(d, d, k)); for (i in 1:k) Sg[, , i] <- rs(d)
  pr <- runif(k); pr <- pr / sum(pr); z <- matrix(runif(n * k), n, k); z <- z / rowSums(z); cl <- apply(z, 1, which.max)
  if (length(unique(cl)) < k) next
  x <- matrix(rnorm(n * d), n, d); cutoff <- c(0.3, 0.5, 0.7)[rep %% 3 + 1]
  r <- tryCatch(mergenormals(x, clustering = cl, probs = pr, muarray = mu, Sigmaarray = Sg, z = z, method = "bhat", cutoff = cutoff), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, d, k, cutoff, pr, as.vector(mu), as.vector(aperm(Sg, c(2, 1, 3))), as.vector(t(z)), as.vector(t(x)))
  v <- c(length(r$valuemerged), sum(r$valuemerged * seq_along(r$valuemerged)), sum(r$mergedtonumbers * seq_along(r$mergedtonumbers)), length(r$clusternumbers))
  for (j in 0:3) cases[[length(cases) + 1]] <- case("mnb", c(a, j), v[j + 1], rel = 1e-8, abs = 1e-10)
}
# "mnd": the same layout, method = "demp" (cutoffs 0.02, 0.05, 0.1)
for (rep in 1:7) {
  d <- sample(1:3, 1); k <- sample(3:6, 1); n <- sample(40:120, 1)
  mu <- matrix(rnorm(k * d), d, k); Sg <- array(0, c(d, d, k)); for (i in 1:k) Sg[, , i] <- rs(d)
  pr <- runif(k); pr <- pr / sum(pr); z <- matrix(rexp(n * k), n, k) ^ 2; z <- z / rowSums(z); cl <- apply(z, 1, which.max)
  if (length(unique(cl)) < k) next
  x <- matrix(rnorm(n * d), n, d); cutoff <- c(0.02, 0.05, 0.1)[rep %% 3 + 1]
  r <- tryCatch(mergenormals(x, clustering = cl, probs = pr, muarray = mu, Sigmaarray = Sg, z = z, method = "demp", cutoff = cutoff), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, d, k, cutoff, pr, as.vector(mu), as.vector(aperm(Sg, c(2, 1, 3))), as.vector(t(z)), as.vector(t(x)))
  v <- c(length(r$valuemerged), sum(r$valuemerged * seq_along(r$valuemerged)), sum(r$mergedtonumbers * seq_along(r$mergedtonumbers)), length(r$clusternumbers))
  for (j in 0:3) cases[[length(cases) + 1]] <- case("mnd", c(a, j), v[j + 1], rel = 1e-8, abs = 1e-10)
}
# "nmb" / "nmd": a clustering with a noise cluster (label 0, its probability first in probs and its z column first); the same layout as "mnb" / "mnd" but probs has k + 1 entries
# (noise first) and z is n by k + 1 (noise column first). fpc moves the noise last and merges the components 1 .. k
for (meth in c("bhat", "demp")) {
  made <- 0; rep <- 0
  while (made < 6 && rep < 60) {
    rep <- rep + 1
    d <- sample(1:3, 1); k <- sample(3:6, 1); n <- sample(40:100, 1)
    mu <- matrix(rnorm(k * d), d, k); Sg <- array(0, c(d, d, k)); for (i in 1:k) Sg[, , i] <- rs(d)
    pr <- runif(k + 1); pr <- pr / sum(pr); z <- matrix(rexp(n * (k + 1)), n, k + 1)^2; z <- z / rowSums(z)
    cl <- apply(z[, -1], 1, which.max); cl[sample(n, 6)] <- 0
    if (length(unique(cl)) < k + 1) next
    x <- matrix(rnorm(n * d), n, d); cutoff <- if (meth == "bhat") c(0.3, 0.5, 0.7)[rep %% 3 + 1] else c(0.02, 0.05, 0.1)[rep %% 3 + 1]
    r <- tryCatch(mergenormals(x, clustering = cl, probs = pr, muarray = mu, Sigmaarray = Sg, z = z, method = meth, cutoff = cutoff), error = function(e) NULL)
    if (is.null(r)) next
    made <- made + 1
    a <- c(n, d, k, cutoff, pr, as.vector(mu), as.vector(aperm(Sg, c(2, 1, 3))), as.vector(t(z)), as.vector(t(x)))
    v <- c(length(r$valuemerged), sum(r$valuemerged * seq_along(r$valuemerged)), sum(r$mergedtonumbers * seq_along(r$mergedtonumbers)), length(r$clusternumbers))
    for (j in 0:3) cases[[length(cases) + 1]] <- case(if (meth == "bhat") "nmb" else "nmd", c(a, j), v[j + 1], rel = 1e-8, abs = 1e-10)
  }
}
emit("fpc_bhat", "fpc", list(cases))
