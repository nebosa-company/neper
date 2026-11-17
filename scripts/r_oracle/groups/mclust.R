# mclust: nMclustParams, bic, adjustedRandIndex, map.
#   "npar" (model index, d, G, noise, equalPro) "bic" (model index, loglik, n, d, G, noise, equalPro) "ari" (n, x[n], y[n] as 0-based codes) "map" (n, k, z[n k] column-major, position)
suppressMessages(library(mclust))
cases <- list()
add <- function(fn, args, want, tol = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261118)
mods <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
for (rep in 1:60) {
  mi <- sample(length(mods), 1); m <- mods[mi]; d <- if (mi <= 2) 1 else sample(2:6, 1); g <- sample(1:7, 1); no <- sample(c(TRUE, FALSE), 1); ep <- sample(c(TRUE, FALSE), 1)
  add("npar", c(mi - 1, d, g, no, ep), nMclustParams(m, d, g, no, ep)); n <- sample(30:500, 1); ll <- -runif(1, 50, 900)
  add("bic", c(mi - 1, ll, n, d, g, no, ep), bic(m, ll, n, d, g, no, ep))
}
for (rep in 1:40) {
  n <- sample(10:200, 1); kx <- sample(1:5, 1); ky <- sample(1:5, 1); x <- sample(kx, n, TRUE); y <- if (rep %% 3 == 0) x else sample(ky, n, TRUE)
  x <- match(x, sort(unique(x))); y <- match(y, sort(unique(y))); add("ari", c(n, x - 1, y - 1), adjustedRandIndex(x, y))
}
for (rep in 1:20) {
  n <- sample(5:40, 1); k <- sample(2:5, 1); z <- matrix(runif(n * k), n, k); z <- z / rowSums(z); z[sample(n, 1), 1:2] <- 0.5; mp <- map(z, warn = FALSE)
  for (i in seq_len(n)) add("map", c(n, k, z, i - 1), mp[i])
}
# me(data, model, z): "me" (model code + 10 when equalPro, n, p, G, id, x[n p] column-major, z[n G] column-major); model code 0 EII 1 VII 2 EEI 3 VVI 4 EEE 5 VVV 6 EVI 7 EVV 8 EEV;
# id 0 loglik 1 iterations 2 sum(pos * pro) 3 sum(pos * mean) 4 sum(pos * sigma) 5 sum(pos * z)
mnames <- c("EII", "VII", "EEI", "VVI", "EEE", "VVV", "EVI", "EVV", "EEV")
for (rep in 1:144) {
  mc <- (rep - 1) %% 9; eqp <- rep > 72; n <- sample(30:90, 1); p <- sample(2:3, 1); G <- sample(2:3, 1)
  cl <- sample(G, n, TRUE); x <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.5, 1.5), each = n) + 2.5 * (cl - 1)
  z0 <- unmap(cl); k <- sample(n, max(4, n %/% 8)); z0[k, ] <- matrix(1 / G, length(k), G)
  if (eqp && mc %in% c(3, 7)) next  # mevvi and meevv with equal proportions do not follow the textbook M step (not matched)
  o <- tryCatch(me(x, mnames[mc + 1], z0, control = emControl(equalPro = eqp)), error = function(e) NULL)
  if (is.null(o) || is.na(o$loglik) || !is.null(attr(o, "warn")) || attr(o, "returnCode") != 0) next
  st <- c(o$loglik, attr(o, "info")[["iterations"]], sum(seq_len(G) * o$parameters$pro), sum(seq_along(o$parameters$mean) * as.vector(o$parameters$mean)),
          sum(seq_along(o$parameters$variance$sigma) * as.vector(o$parameters$variance$sigma)), sum(seq_along(o$z) * as.vector(o$z)))
  for (j in 0:5) add("me", c(mc + 10 * eqp, n, p, G, j, x, z0), st[j + 1], if (j == 1) 1e-12 else 1e-7)
}
# hc(data, "EII"): "hc" (n, p, index, X[n p]) index 0 .. 2 (n - 1) - 1 into the merge pairs, column by column
for (rep in 1:25) {
  n <- sample(6:40, 1); p <- sample(2:4, 1); X <- matrix(rnorm(n * p), n, p); h <- unclass(hc(X, modelName = "EII"))[1:2, ]
  v <- as.vector(h); for (q in seq_along(v)) add("hc", c(n, p, q - 1, X), v[q], 0)
}
emit("mclust", "mclust", list(cases))
