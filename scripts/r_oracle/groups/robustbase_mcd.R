# robustbase covMcd for two or more variables (FastMCD), seeded.
#   "mcdp" args (seed, n, p, alpha, nsamp, x[n*p] row-major, which): element `which` of c(raw.center, raw.cov, center, cov, crit) (matrices row-major)
suppressMessages(library(robustbase))
cases <- list()
set.seed(20261224)
for (rep in 1:14) {
  p <- sample(2:4, 1); n <- sample(30:60, 1)
  if (rep %% 7 == 0) { n <- sample(c(12, 14, 16, 18, 20), 1) }  # n small enough for every elemental subset to be tried when p = 2
  x <- matrix(round(rnorm(n * p, 1, 2), 3), n, p) %*% chol(0.5 * diag(p) + 0.5)
  x <- round(x, 4)
  k <- max(1, n %/% 6); x[sample(n, k), ] <- x[sample(n, k), ] + 8
  alpha <- c(0.5, 0.6, 0.75, 0.9)[1 + rep %% 4]; if (n <= 20) alpha <- 0.75
  sd0 <- sample(1:100000, 1)
  set.seed(sd0)
  ns <- c(500, 200, 1000)[1 + rep %% 3]; set.seed(sd0)
  r <- tryCatch(suppressWarnings(covMcd(x, alpha = alpha, nsamp = ns)), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$raw.center, as.vector(t(r$raw.cov)), r$center, as.vector(t(r$cov)), r$crit)
  for (w in seq_along(v)) cases[[length(cases) + 1]] <- case("mcdp", c(sd0, n, p, alpha, ns, as.vector(t(x)), w - 1), v[w], rel = 1e-9, abs = 1e-12)
}
emit("robustbase_mcd", "robustbase", list(cases))
