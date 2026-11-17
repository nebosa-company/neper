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
emit("nmf", "NMF", list(cases))
