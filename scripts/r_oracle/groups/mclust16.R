# mclust, sixteenth part: sim() from the M step parameters of EEV, VEV and EVV (the orientation matrices come from dgesvd).
# "ori" (model idx, n, p, G, nsim, seed, id, X[n p], z[n G]): id 0 sum(q * group), 1 sum(q * x), 2 sum(q * orientation)
suppressMessages(library(mclust))
cases <- list()
set.seed(20261224)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
for (rep in 1:45) {
  mi <- c(12, 13, 14)[(rep - 1) %% 3 + 1]; mn <- tbl[mi + 1]
  p <- sample(2:4, 1); G <- sample(2:3, 1); n <- sample(40:90, 1); cl <- sample(G, n, TRUE)
  X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.5, 1.5), each = n) + 2.5 * (cl - 1)
  if (p > 1) X[, 2] <- X[, 2] + 0.6 * X[, 1]
  z0 <- unmap(cl); k <- sample(n, max(4, n %/% 8)); z0[k, ] <- matrix(1 / G, length(k), G)
  ms <- tryCatch(suppressWarnings(mstep(X, mn, z0)), error = function(e) NULL)
  if (is.null(ms)) next
  nsim <- sample(30:60, 1); sd <- sample(1:100000, 1)
  s <- tryCatch(suppressWarnings(sim(mn, ms$parameters, nsim, seed = sd)), error = function(e) NULL)
  if (is.null(s)) next
  a <- c(mi, n, p, G, nsim, sd)
  sq <- function(m) sum(seq_along(m) * as.vector(m))
  add <- function(id, want) cases[[length(cases) + 1]] <<- case("ori", c(a, id, X, z0), want, rel = 1e-8, abs = 1e-9)
  add(0, sq(s[, 1])); add(1, sq(s[, -1])); add(2, sq(ms$parameters$variance$orientation))
}
emit("mclust16", "mclust", list(cases))
