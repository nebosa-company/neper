# fpc: ridgeline, dridgeline, piridge.zeroes, ridgeline.diagnosis and mergenormals(method = "ridge.uni" / "ridge.ratio").
#   "rl": (d, alpha, mu1[d], mu2[d], S1 d by d row-major, S2); the answer is sum(i * ridgeline[i])
#   "pz": (d, prop, by, what, mu1, mu2, S1, S2); what 0 number.zeroes, 1 sum(i * estimated.roots[i]), 2 sum(i * dridgeline(estimated.roots)[i])
#   "rd": (d, k, by, ratio, cutoff, what, probs[k], mu k by d row-major, Sigma k blocks of d by d row-major); the answer is sum over the upper triangle of
#         (position) * connection.matrix (what 0) or ratiomatrix (what 1), position counting the pairs (i, j), i < j, in column-major order
#   "mnu" / "mnr": (n, d, k, cutoff, by, probs[k], mu k by d, Sigma blocks, z n by k row-major, x n by d row-major, stat): mergenormals ridge.uni / ridge.ratio,
#         stat 0 length(valuemerged) 1 sum(valuemerged * position) 2 sum(mergedtonumbers * position) 3 length(clusternumbers)
suppressMessages(library(fpc))
cases <- list()
set.seed(20269971)
rs <- function(d, sc = 1) { A <- matrix(rnorm(d * d), d, d); (crossprod(A) + diag(d) * 0.3) * sc }
flat <- function(m) as.vector(t(unclass(as.matrix(m))))
add <- function(nm, args, want, rel = 1e-8, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = rel, abs = abs)
for (rep in 1:20) {
  d <- sample(1:3, 1); m1 <- rnorm(d); m2 <- rnorm(d); S1 <- rs(d); S2 <- rs(d); al <- runif(1)
  add("rl", c(d, al, m1, m2, flat(S1), flat(S2)), sum(seq_len(d) * ridgeline(al, m1, m2, S1, S2)))
}
for (rep in 1:24) {
  d <- sample(1:3, 1); m1 <- rnorm(d); m2 <- m1 + rnorm(d) * c(0.5, 1.5, 3)[rep %% 3 + 1]; S1 <- rs(d, 0.5); S2 <- rs(d, 0.5); prop <- runif(1, 0.2, 0.8); by <- c(0.01, 0.005)[rep %% 2 + 1]
  r <- piridge.zeroes(prop, m1, m2, S1, S2, by = by)
  if (r$number.zeroes == 0) next
  dr <- dridgeline(r$estimated.roots, prop, m1, m2, S1, S2)
  hdr <- c(d, prop, by)
  add("pz", c(hdr, 0, m1, m2, flat(S1), flat(S2)), r$number.zeroes, rel = 0, abs = 0)
  add("pz", c(hdr, 1, m1, m2, flat(S1), flat(S2)), sum(seq_along(r$estimated.roots) * r$estimated.roots))
  add("pz", c(hdr, 2, m1, m2, flat(S1), flat(S2)), sum(seq_along(dr) * dr))
}
mkmix <- function(d, k, sep) {
  mu <- matrix(rnorm(k * d) * sep, d, k); Sg <- array(0, c(d, d, k)); for (i in 1:k) Sg[, , i] <- rs(d, 0.6)
  pr <- runif(k); pr <- pr / sum(pr); list(mu = mu, Sg = Sg, pr = pr)
}
for (rep in 1:14) {
  d <- sample(1:3, 1); k <- sample(3:5, 1); m <- mkmix(d, k, c(0.7, 1.5)[rep %% 2 + 1]); by <- 0.01; ratio <- rep %% 2 == 0; cutoff <- c(0.2, 0.4)[rep %% 3 %% 2 + 1]
  r <- ridgeline.diagnosis(m$pr, m$mu, m$Sg, k = k, compute.ratio = ratio, by = by, ratiocutoff = if (ratio) cutoff else NULL, ridgelineplot = "none")
  pairs <- which(upper.tri(diag(k)), arr.ind = TRUE); pairs <- pairs[order(pairs[, 2], pairs[, 1]), , drop = FALSE]
  a <- c(d, k, by, as.numeric(ratio), if (ratio) cutoff else -1)
  body <- c(m$pr, flat(t(m$mu)), as.vector(aperm(m$Sg, c(2, 1, 3))))
  cv <- sum(seq_len(nrow(pairs)) * r$connection.matrix[pairs])
  add("rd", c(a, 0, body), cv, rel = 0, abs = 0)
  if (ratio) add("rd", c(a, 1, body), sum(seq_len(nrow(pairs)) * r$ratiomatrix[pairs]))
}
for (meth in c("ridge.uni", "ridge.ratio")) {
  made <- 0; rep <- 0
  while (made < 14 && rep < 100) {
    rep <- rep + 1
    d <- sample(1:2, 1); k <- sample(3:5, 1); n <- sample(40:100, 1); m <- mkmix(d, k, c(0.6, 1.0, 1.6)[rep %% 3 + 1])
    z <- matrix(rexp(n * k), n, k)^2; z <- z / rowSums(z); cl <- apply(z, 1, which.max)
    if (length(unique(cl)) < k) next
    x <- matrix(rnorm(n * d), n, d); cutoff <- c(0.2, 0.4, 0.6)[rep %% 3 + 1]; by <- 0.01
    r <- tryCatch(suppressWarnings(mergenormals(x, clustering = cl, probs = m$pr, muarray = m$mu, Sigmaarray = m$Sg, z = z, method = meth, cutoff = cutoff, by = by)), error = function(e) NULL)
    if (is.null(r)) next
    made <- made + 1
    a <- c(n, d, k, cutoff, by, m$pr, flat(t(m$mu)), as.vector(aperm(m$Sg, c(2, 1, 3))), as.vector(t(z)), as.vector(t(x)))
    v <- c(length(r$valuemerged), sum(r$valuemerged * seq_along(r$valuemerged)), sum(r$mergedtonumbers * seq_along(r$mergedtonumbers)), length(r$clusternumbers))
    for (j in 0:3) add(if (meth == "ridge.uni") "mnu" else "mnr", c(a, j), v[j + 1])
  }
}
emit("fpc_ridge", "fpc", list(cases))
