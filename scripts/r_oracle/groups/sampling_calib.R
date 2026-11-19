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
emit("sampling_calib", "sampling", list(cases))
