# mclust, second part: the EM fits of the models the first group leaves out (E, V, VEI, VEV, EVE, VEE, VVE) and equal proportions.
# "me2" (model index in the package table E 0 V 1 EII 2 VII 3 EEI 4 VEI 5 EVI 6 VVI 7 EEE 8 EVE 9 VEE 10 VVE 11 EEV 12 VEV 13 EVV 14 VVV 15, equalPro, n, p, G, id, x[n p], z[n G]) column-major;
# id 0 loglik, 1 iterations, 2 sum(pos * pro) + sum(pos * mean) + sum(pos * sigma), 3 sum(pos * z)
suppressMessages(library(mclust))
cases <- list()
set.seed(20261130)
mods <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
fit <- function(mi, eqp, n, p, G, tol_note = NULL) {
  cl <- sample(G, n, TRUE)
  sc <- runif(p, 0.5, 1.5)
  x <- matrix(rnorm(n * p), n, p) * rep(sc, each = n) * (1 + 0.4 * (cl - 1)) + 2.5 * (cl - 1)
  if (p > 1) x[, 2] <- x[, 2] + 0.6 * x[, 1]
  z0 <- unmap(cl); k <- sample(n, max(4, n %/% 8)); z0[k, ] <- matrix(1 / G, length(k), G)
  o <- tryCatch(suppressWarnings(me(x, mods[mi + 1], z0, control = emControl(equalPro = eqp))), error = function(e) NULL)
  if (is.null(o) || is.na(o$loglik) || attr(o, "returnCode") != 0) return(invisible(NULL))
  inf <- attr(o, "info")
  pr <- o$parameters
  sg <- pr$variance$sigma; if (mi == 0) sg <- rep(sg, G)
  st <- c(o$loglik, inf[[1]], sum(seq_len(G) * pr$pro) + sum(seq_along(pr$mean) * as.vector(pr$mean)) + sum(seq_along(sg) * as.vector(sg)), sum(seq_along(o$z) * as.vector(o$z)))
  for (j in 0:3) cases[[length(cases) + 1]] <<- case("me2", c(mi, as.numeric(eqp), n, p, G, j, x, z0), st[j + 1], rel = if (j == 1) 1e-12 else 1e-6, abs = if (j == 1) 0 else 1e-9)
}
for (mi in c(5, 9, 10, 11, 13)) for (eqp in c(FALSE, TRUE)) for (rep in 1:5) fit(mi, eqp, sample(40:70, 1), sample(2:3, 1), sample(2:3, 1))
for (mi in c(0, 1)) for (eqp in c(FALSE, TRUE)) for (rep in 1:4) fit(mi, eqp, sample(30:80, 1), 1, sample(2:4, 1))
emit("mclust2", "mclust", list(cases))
