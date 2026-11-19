# sampling: calib(Xs, d, total, q, method = "linear" / "raking"). Args: (method 0 linear 1 raking, n, p, i, Xs[n * p] row-major, d[n], total[p], q[n]): the g-weight i (0-based).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262326)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("cb", args, want, rel = 1e-5, abs = 1e-8)
for (rep in 1:24) {
  method <- (rep - 1) %% 2; n <- sample(30:80, 1); p <- sample(2:4, 1)
  Xs <- cbind(1, matrix(round(runif(n * (p - 1), 0, 5), 3), n)); d <- round(runif(n, 1, 4), 3); q <- if (rep %% 3 == 0) round(runif(n, 0.5, 2), 3) else rep(1, n)
  total <- colSums(Xs * d) * runif(p, 0.9, 1.1)
  g <- tryCatch(suppressWarnings(calib(Xs, d, total, q, method = c("linear", "raking")[method + 1])), error = function(e) NULL)
  if (is.null(g) || any(!is.finite(g))) next
  for (i in seq(1, n, by = 4)) add(c(method, n, p, i - 1, as.vector(t(Xs)), d, total, q), g[i])
}
# truncated: args (2, n, p, i, Xs, d, total, q, low, upp); only data sets where R converges are kept.
for (rep in 1:12) {
  n <- sample(40:90, 1); p <- sample(2:3, 1)
  Xs <- cbind(1, matrix(round(runif(n * (p - 1), 0, 5), 3), n)); d <- round(runif(n, 1, 4), 3); q <- rep(1, n)
  total <- colSums(Xs * d) * runif(p, 0.85, 1.15); low <- 0.6; upp <- 3
  g <- tryCatch(suppressWarnings(capture.output(gg <- calib(Xs, d, total, q, method = "truncated", bounds = c(low, upp)))), error = function(e) NULL)
  if (is.null(g) || length(g) > 0 || is.null(gg) || any(!is.finite(gg))) next
  for (i in seq(1, n, by = 4)) add(c(2, n, p, i - 1, as.vector(t(Xs)), d, total, q, low, upp), gg[i])
}
# logit: args (3, n, p, i, Xs, d, total, q, low, upp).
for (rep in 1:12) {
  n <- sample(40:90, 1); p <- sample(2:3, 1)
  Xs <- cbind(1, matrix(round(runif(n * (p - 1), 0, 5), 3), n)); d <- round(runif(n, 1, 4), 3); q <- rep(1, n)
  total <- colSums(Xs * d) * runif(p, 0.85, 1.15); low <- 0.6; upp <- 3
  g <- tryCatch(suppressWarnings(capture.output(gg <- calib(Xs, d, total, q, method = "logit", bounds = c(low, upp)))), error = function(e) NULL)
  if (is.null(g) || length(g) > 0 || is.null(gg) || any(!is.finite(gg))) next
  for (i in seq(1, n, by = 4)) add(c(3, n, p, i - 1, as.vector(t(Xs)), d, total, q, low, upp), gg[i])
}
emit("sampling_calib", "sampling", list(cases))
