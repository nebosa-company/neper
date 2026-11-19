# mirt(data, 1, itemtype = "2PL"): "tpl" args (n, j, y[n * j] row-major 0/1, k) k = 2 (item - 1) the slope a1 and 2 (item - 1) + 1 the intercept d of that item, 2 j the log-likelihood
suppressMessages(library(mirt))
cases <- list()
set.seed(20271219)
for (rep in 1:5) {
  N <- sample(300:500, 1); J <- sample(4:6, 1); th <- rnorm(N); a <- runif(J, 0.8, 1.8); d <- rnorm(J, 0, 0.8)
  Y <- sapply(1:J, function(j) rbinom(N, 1, plogis(a[j] * th + d[j]))); colnames(Y) <- paste0("i", 1:J)
  f <- tryCatch(mirt(Y, 1, itemtype = "2PL", verbose = FALSE, TOL = 1e-9), error = function(e) NULL)
  if (is.null(f) || !f@OptimInfo$converged) next
  cf <- coef(f, simplify = TRUE, IRTpars = FALSE)$items
  if (any(abs(cf[, "a1"]) > 4)) next
  v <- c(as.vector(t(cf[, c("a1", "d")])), as.numeric(logLik(f)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("tpl", c(N, J, as.vector(t(Y)), k - 1), as.numeric(v[k]), rel = if (k == length(v)) 1e-6 else 1e-2, abs = if (k == length(v)) 1e-4 else 5e-3)
}
# itemtype = "Rasch": "rasch" args (n, j, y[n * j], k) k 0 .. j - 1 the intercepts, j the latent variance, j + 1 the log-likelihood
for (rep in 1:6) {
  N <- sample(300:500, 1); J <- sample(4:6, 1); th <- rnorm(N, 0, runif(1, 0.8, 1.6)); d <- rnorm(J, 0, 0.8)
  Y <- sapply(1:J, function(j) rbinom(N, 1, plogis(th + d[j]))); colnames(Y) <- paste0("i", 1:J)
  f <- tryCatch(mirt(Y, 1, itemtype = "Rasch", verbose = FALSE, TOL = 1e-9), error = function(e) NULL)
  if (is.null(f) || !f@OptimInfo$converged) next
  cf <- coef(f, simplify = TRUE); v <- c(cf$items[, "d"], cf$cov[1, 1], as.numeric(logLik(f)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("rasch", c(N, J, as.vector(t(Y)), k - 1), as.numeric(v[k]), rel = if (k == length(v)) 1e-6 else 1e-2, abs = if (k == length(v)) 1e-4 else 5e-3)
}
# itemtype = "graded", K ordered categories coded 0 .. K - 1: "graded" args (n, j, K, y[n * j], k) k item * K the slope and item * K + 1 .. item * K + K - 1 the intercepts of the item, j K the log-likelihood
for (rep in 1:10) {
  N <- sample(300:450, 1); J <- sample(3:4, 1); K <- sample(3:4, 1); th <- rnorm(N); a <- runif(J, 0.9, 1.8)
  Y <- sapply(1:J, function(j) { d <- sort(rnorm(K - 1, 0, 1), decreasing = TRUE); pr <- plogis(outer(a[j] * th, d, "+")); u <- runif(N); rowSums(u < pr) }); colnames(Y) <- paste0("i", 1:J)
  if (any(apply(Y, 2, function(v) length(unique(v))) < K)) next
  f <- tryCatch(mirt(Y, 1, itemtype = "graded", verbose = FALSE, TOL = 1e-9), error = function(e) NULL)
  if (is.null(f) || !f@OptimInfo$converged) next
  cf <- coef(f, simplify = TRUE, IRTpars = FALSE)$items
  if (any(abs(cf[, 1]) > 4)) next
  v <- c(as.vector(t(cf[, 1:K])), as.numeric(logLik(f)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("graded", c(N, J, K, as.vector(t(Y)), k - 1), as.numeric(v[k]), rel = if (k == length(v)) 1e-6 else 2e-2, abs = if (k == length(v)) 1e-4 else 1e-2)
}
emit("mirt", "mirt", list(cases))
