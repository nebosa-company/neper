# mclust, tenth part: priors for EEI VEI EVI VVI EEV VEV.
# "pme" (model idx, n, p, G, id, X[n p], z[n G]): me with prior = priorControl(); id 0 loglik, 1 iterations, 2 sum(q * (pro, mean, sigma)), 3 sum(q * z)
# "pms" (same layout): mstep with the prior; id 0 pro, 1 mean, 2 sigma checksums
# "pdp" (model idx, n, p, G, id, X[n p]): defaultPrior; id 0 dof, 1 sum(q * mean), 2 sum(q * scale)
suppressMessages(library(mclust))
cases <- list()
set.seed(20261217)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
for (rep in 1:42) {
  mi <- c(4, 5, 6, 7, 12, 13)[(rep - 1) %% 6 + 1]; mn <- tbl[mi + 1]
  p <- sample(2:3, 1); G <- sample(2:3, 1); n <- sample(40:90, 1); cl <- sample(G, n, TRUE)
  X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.5, 1.5), each = n) + 2.5 * (cl - 1)
  z0 <- unmap(cl); k <- sample(n, max(4, n %/% 8)); z0[k, ] <- matrix(1 / G, length(k), G)
  a <- c(mi, n, p, G)
  dp <- defaultPrior(X, G, mn)
  sc <- dp$scale
  cases[[length(cases) + 1]] <- case("pdp", c(a, 0, X), dp$dof, rel = 1e-12, abs = 0)
  cases[[length(cases) + 1]] <- case("pdp", c(a, 1, X), sum(seq_along(dp$mean) * dp$mean), rel = 1e-12, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("pdp", c(a, 2, X), sum(seq_along(sc) * as.vector(sc)), rel = 1e-12, abs = 1e-12)
  o <- tryCatch(suppressWarnings(me(X, mn, z0, prior = priorControl())), error = function(e) NULL)
  if (!is.null(o) && !is.na(o$loglik) && attr(o, "returnCode") == 0) {
    P <- o$parameters; sg <- P$variance$sigma; if (mn == "E") sg <- rep(sg, G)
    st <- c(o$loglik, attr(o, "info")[[1]], sum(seq_len(G) * P$pro) + sum(seq_along(P$mean) * as.vector(P$mean)) + sum(seq_along(sg) * as.vector(sg)), sum(seq_along(o$z) * as.vector(o$z)))
    for (j in 0:3) cases[[length(cases) + 1]] <- case("pme", c(a, j, X, z0), st[j + 1], rel = if (j == 1) 0 else 1e-6, abs = if (j == 1) 0 else 1e-9)
  }
  ms <- tryCatch(suppressWarnings(mstep(X, mn, z0, prior = priorControl())), error = function(e) NULL)
  if (!is.null(ms) && attr(ms, "returnCode") == 0) {
    P <- ms$parameters; sg <- P$variance$sigma; if (mn == "E") sg <- rep(sg, G)
    cases[[length(cases) + 1]] <- case("pms", c(a, 0, X, z0), sum(seq_along(P$pro) * P$pro), rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("pms", c(a, 1, X, z0), sum(seq_along(P$mean) * as.vector(P$mean)), rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("pms", c(a, 2, X, z0), sum(seq_along(sg) * as.vector(sg)), rel = 1e-9, abs = 1e-12)
  }
}
emit("mclust10", "mclust", list(cases))
