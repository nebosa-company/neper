# qgraph::cor_auto on data mixing continuous and ordinal columns (lavaan two-step polychoric / polyserial / Pearson).
#   fn "ca_cont" "ca_ord" "ca_mix": args (nobs, p, detect, levelMax, ordFlag[p], data[nobs * p] column-major with NaN as NA):
#   the position-weighted sum of the correlation matrix (column-major); the three names only separate the tolerances
suppressMessages(library(qgraph))
cases <- list()
ws <- function(v) sum(as.vector(v) * seq_along(as.vector(v)))
set.seed(20271202)
mk <- function(n, p, types, na_rate) {
  A <- matrix(rnorm(p * p), p, p); L <- diag(p) + runif(1, 0.3, 1.5) * A %*% t(A) / p
  lat <- matrix(rnorm(n * p), n, p) %*% chol(L)
  d <- matrix(0, n, p)
  for (j in 1:p) {
    if (types[j] == "c") d[, j] <- round(lat[, j] * runif(1, 0.5, 2) + runif(1, -2, 2), 3)
    else if (types[j] == "i") d[, j] <- round(lat[, j] * 4) + 20
    else { k <- as.integer(types[j]); cuts <- sort(rnorm(k - 1, 0, 0.8)); d[, j] <- as.numeric(cut(lat[, j], c(-Inf, cuts, Inf))) }
  }
  if (na_rate > 0) d[matrix(runif(n * p) < na_rate, n, p)] <- NA
  d
}
for (it in 1:54) {
  n <- sample(80:300, 1); p <- sample(3:7, 1)
  kind <- c("ca_cont", "ca_ord", "ca_mix")[1 + it %% 3]
  types <- switch(kind, ca_cont = rep("c", p), ca_ord = sample(c("2", "3", "4", "5", "7"), p, TRUE), ca_mix = c(sample(c("c", "i"), 1), "c", sample(c("2", "3", "4", "6"), p - 2, TRUE)))
  if (kind == "ca_mix") types <- sample(types)
  na_rate <- if (it %% 4 == 0) 0.04 else 0
  d <- mk(n, p, types, na_rate)
  if (any(colSums(!is.na(d)) < 10)) next
  r <- tryCatch(suppressWarnings(suppressMessages(cor_auto(d, verbose = FALSE))), error = function(e) NULL)
  if (is.null(r) || ncol(r) != p || any(abs(r[upper.tri(r)]) > 0.95)) next
  tol <- c(ca_cont = 1e-10, ca_ord = 1e-6, ca_mix = 1e-5)[[kind]]
  cases[[length(cases) + 1]] <- case(kind, c(n, p, 1, 7, rep(0, p), as.vector(d)), ws(r), rel = tol, abs = tol)
}
emit("qgraphcor", c("qgraph", "lavaan"), list(cases))
