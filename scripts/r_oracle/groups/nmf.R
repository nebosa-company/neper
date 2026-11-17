# NMF (theta 0.5 unless a nsNMF case says otherwise): brunet (method 0) and lee (method 1) after nmf(x, rank, method, seed = integer); args (n, p, r, method, seed, x[n*p] column-major, idx) where idx 0 is the iteration count, then W (n*r) then H (r*p) in column-major order
suppressMessages(library(NMF))
cases <- list()
set.seed(20261117)
for (rep in 1:40) {
  n <- sample(6:20, 1); p <- sample(5:12, 1); r <- sample(2:4, 1); me <- rep %% 2; sd <- sample(1:100000, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = if (me == 0) "brunet" else "lee", seed = sd)), error = function(e) NULL)
  if (is.null(res)) next
  mth <- if (me == 0) "brunet" else "lee"
  set.seed(sd); mx <- max(x)
  w <- matrix(runif(n * r) * mx, n, r); h <- matrix(runif(r * p) * mx, r, p)
  eps <- .Machine$double.eps; consold <- matrix(0, p, p); inc <- 0; iters <- 2000
  for (i in 1:2000) {
    if (me == 0) { wh <- w %*% h; h <- h * (t(w) %*% (x / wh)) / colSums(w); wh <- w %*% h; w <- w * ((x / wh) %*% t(h)) / rep(rowSums(h), each = n); if (i %% 10 == 0) { h <- pmax(h, eps); w <- pmax(w, eps) } }
    else { h <- h * (t(w) %*% x) / ((t(w) %*% w) %*% h + 1e-9); w <- w * (x %*% t(h)) / (w %*% (h %*% t(h)) + 1e-9); w <- t(t(w) / colSums(w)) }
    if (i %% 10 == 0) { idx <- apply(h, 2, which.max); cons <- outer(idx, idx, function(a, b) ifelse(a == b, 1, 0)); if (all(cons == consold)) inc <- inc + 1 else { consold <- cons; inc <- 0 }; if (inc > 40) { iters <- i; break } }
  }
  v <- c(NA, as.vector(basis(res)), as.vector(coef(res)))
  v[1] <- iters
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmf", c(n, p, r, me, sd, 0.5, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else if (me == 0) 1e-6 else 1e-8, abs = if (q == 1) 0 else if (me == 0) 1e-8 else 1e-10)
}
# KL (method 2) and Frobenius (method 3): the same updates under the "stationary" stopping rule; the iteration count is the fit's own niter
for (rep in 1:24) {
  n <- sample(6:16, 1); p <- sample(5:10, 1); r <- sample(2:3, 1); me <- 2 + rep %% 2; sd <- sample(1:100000, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = if (me == 2) "KL" else "Frobenius", seed = sd)), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmf", c(n, p, r, me, sd, 0.5, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 300 else 1e-8)
}
# nsNMF (method 4): the smoothing theta
for (rep in 1:20) {
  n <- sample(6:16, 1); p <- sample(5:10, 1); r <- sample(2:4, 1); sd <- sample(1:100000, 1); th <- c(0.2, 0.5, 0.8)[sample(3, 1)]
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = "nsNMF", seed = sd, theta = th)), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmf", c(n, p, r, 4, sd, th, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 0 else 1e-8)
}
# offset (method 5): a feature-specific baseline, seeded at random after W and H
for (rep in 1:20) {
  n <- sample(6:16, 1); p <- sample(5:10, 1); r <- sample(2:4, 1); sd <- sample(1:100000, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = "offset", seed = sd)), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmf", c(n, p, r, 5, sd, 0.5, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 0 else 1e-8)
}
# the nndsvd seed (the method code plus 10 for densify none, plus 20 for average), brunet and lee
for (rep in 1:30) {
  n <- sample(6:16, 1); p <- sample(5:10, 1); r <- sample(2:4, 1); me <- rep %% 2; dn <- 1 + (rep %/% 2) %% 2
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = if (me == 0) "brunet" else "lee", seed = list(method = "nndsvd", densify = if (dn == 1) "none" else "average"))), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  if (any(!is.finite(v))) next
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmf", c(n, p, r, 10 * dn + me, 0, 0.5, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 0 else 1e-8)
}
# ls-nmf (method 6) with unit weights: the R-level Euclidean updates under the stationary stop, count within 300
for (rep in 1:20) {
  n <- sample(6:16, 1); p <- sample(5:10, 1); r <- sample(2:3, 1); sd <- sample(1:100000, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = "ls-nmf", seed = sd, weight = 1)), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmf", c(n, p, r, 6, sd, 0.5, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 300 else 1e-8)
}
# several runs ("nmr": (n, p, r, method, seed, nrun, x, idx)): the streams of RNGseq(nrun, seed), the best fit kept; idx 0 its iteration count, then W, H
for (rep in 1:20) {
  n <- sample(8:16, 1); p <- sample(6:10, 1); r <- sample(2:4, 1); me <- rep %% 2; sd <- sample(1:100000, 1); nr <- sample(2:4, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = if (me == 0) "brunet" else "lee", nrun = nr, seed = sd, .pbackend = NA)), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("nmr", c(n, p, r, me, sd, nr, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 0 else 1e-8)
}
# consensus over the runs ("nmc": the same arguments as nmr; idx 0 the cophenetic correlation, 1 the dispersion, then the consensus matrix column by column)
for (rep in 1:20) {
  n <- sample(8:16, 1); p <- sample(6:10, 1); r <- sample(2:4, 1); me <- rep %% 2; sd <- sample(1:100000, 1); nr <- sample(3:6, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = if (me == 0) "brunet" else "lee", nrun = nr, seed = sd, .pbackend = NA)), error = function(e) NULL)
  if (is.null(res)) next
  cp <- tryCatch(cophcor(res), error = function(e) NA)
  sm <- tryCatch(summary(res), error = function(e) NULL)
  v <- c(cp, dispersion(res), as.vector(consensus(res)), if (is.null(sm)) rep(NA, 7) else c(sm[["silhouette.consensus"]], sm[["silhouette.coef"]], sm[["silhouette.basis"]], sm[["sparseness.basis"]], sm[["sparseness.coef"]], rss(res, x), evar(res, x)))
  for (q in seq_along(v)) if (is.finite(v[q])) cases[[length(cases) + 1]] <- case("nmc", c(n, p, r, me, sd, nr, as.vector(x), q - 1), v[q], rel = 1e-8, abs = 1e-10)
}
# nmfEstimateRank: the measures table is the same fit at each rank with the seed reused ("nmc" cases from its rows)
for (rep in 1:10) {
  n <- sample(8:14, 1); p <- sample(6:9, 1); me <- rep %% 2; sd <- sample(1:100000, 1); nr <- sample(3:4, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  er <- tryCatch(suppressWarnings(nmfEstimateRank(x, 2:3, method = if (me == 0) "brunet" else "lee", nrun = nr, seed = sd, .pbackend = NA)), error = function(e) NULL)
  if (is.null(er)) next
  for (k in 1:2) {
    m <- er$measures[k, ]; r <- m$rank
    v <- list(`0` = m$cophenetic, `1` = m$dispersion, `2` = NA)
    cs <- c(m$cophenetic, m$dispersion)
    for (nm in c("0", "1")) if (is.finite(v[[nm]])) cases[[length(cases) + 1]] <- case("nmc", c(n, p, r, me, sd, nr, as.vector(x), as.numeric(nm)), v[[nm]], rel = 1e-8, abs = 1e-10)
    cases[[length(cases) + 1]] <- case("nmc", c(n, p, r, me, sd, nr, as.vector(x), p * p + 2), m$silhouette.consensus, rel = 1e-8, abs = 1e-10)
    cases[[length(cases) + 1]] <- case("nmc", c(n, p, r, me, sd, nr, as.vector(x), p * p + 3), m$silhouette.coef, rel = 1e-8, abs = 1e-10)
    cases[[length(cases) + 1]] <- case("nmc", c(n, p, r, me, sd, nr, as.vector(x), p * p + 7), m$rss, rel = 1e-8, abs = 1e-10)
    cases[[length(cases) + 1]] <- case("nmc", c(n, p, r, me, sd, nr, as.vector(x), p * p + 8), m$evar, rel = 1e-8, abs = 1e-10)
  }
}
# snmf/r (version 0) and snmf/l (version 1) with the defaults eta = -1, beta = 0.01: args (n, p, r, version, seed, 0.5, x, idx), idx 0 the iterations
for (rep in 1:20) {
  n <- sample(8:16, 1); p <- sample(6:12, 1); r <- sample(2:3, 1); ver <- rep %% 2; sd <- sample(1:100000, 1)
  x <- matrix(round(runif(n * p, 0.1, 5), 4), n, p)
  res <- tryCatch(suppressWarnings(nmf(x, r, method = if (ver == 0) "snmf/r" else "snmf/l", seed = sd)), error = function(e) NULL)
  if (is.null(res)) next
  v <- c(niter(res), as.vector(basis(res)), as.vector(coef(res)))
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("snm", c(n, p, r, ver, sd, 0.5, as.vector(x), q - 1), v[q], rel = if (q == 1) 0 else 1e-6, abs = if (q == 1) 0 else 1e-8)
}
emit("nmf", "NMF", list(cases))
