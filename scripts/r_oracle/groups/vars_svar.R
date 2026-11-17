# vars: SVAR by scoring (A, B and AB models), its standard errors, LR test, impulse responses with bootstrap bands, and fevd.
#   Every case rebuilds its data from the seed as in vars_core. args: (seed, T0, K, p, det, mode, amat K*K row-major with NA free, bmat K*K, extra...),
#   mode 0 A-model, 1 B-model, 2 AB-model
suppressMessages(library(vars))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
H <- 6
gen <- function(seed, T0, K, slope) {
  set.seed(seed)
  A <- matrix(runif(K * K, -0.3, 0.3), K, K)
  y <- matrix(0, T0, K)
  for (t in 2:T0) y[t, ] <- A %*% y[t - 1, ] + rnorm(K) + slope * t
  colnames(y) <- paste0("s", 1:K)
  y
}
wsum <- function(m) sum(as.vector(m) * seq_len(length(m)))
types <- c("none", "const", "trend", "both")
irfws <- function(ir, h) { tot <- 0; pos <- 0; for (imp in names(ir)) for (i in 0:h) for (j in seq_len(ncol(ir[[imp]]))) { pos <- pos + 1; tot <- tot + ir[[imp]][i + 1, j] * pos }; tot }
mat <- function(K, na, fix = NULL) { m <- diag(K); for (e in na) m[e[1], e[2]] <- NA; m }
# (K, mode, A free positions, B free positions)
models <- list(
  list(2, 0, list(c(2, 1)), NULL),
  list(2, 1, NULL, list(c(1, 1), c(2, 1), c(2, 2))),
  list(2, 1, NULL, list(c(1, 1), c(2, 2))),
  list(2, 2, list(c(2, 1)), list(c(1, 1), c(2, 2))),
  list(3, 0, list(c(2, 1), c(3, 1), c(3, 2)), NULL),
  list(3, 0, list(c(2, 1), c(3, 1)), NULL),
  list(3, 1, NULL, list(c(1, 1), c(2, 1), c(2, 2), c(3, 1), c(3, 2), c(3, 3))),
  list(3, 1, NULL, list(c(1, 1), c(2, 1), c(2, 2), c(3, 2), c(3, 3))),
  list(3, 2, list(c(2, 1), c(3, 1), c(3, 2)), list(c(1, 1), c(2, 2), c(3, 3))))
seeds <- c(501, 502, 503, 504, 505, 506, 507, 508, 509)
for (mi in seq_along(models)) {
  md <- models[[mi]]; K <- md[[1]]; mode <- md[[2]]
  T0 <- 120 + 5 * mi; p <- 1 + mi %% 2; det <- if (mi %% 3 == 0) 3 else 1
  y <- gen(seeds[mi], T0, K, 0)
  v <- do.call(VAR, list(y = y, p = p, type = types[det + 1]))
  amat <- if (mode == 1) NULL else mat(K, md[[3]])
  bmat <- if (mode == 0) NULL else { b <- diag(K); b[] <- 0; for (e in md[[4]]) b[e[1], e[2]] <- NA; b }
  s <- try(suppressWarnings(do.call(SVAR, list(x = v, estmethod = "scoring", Amat = amat, Bmat = bmat))), silent = TRUE)
  if (inherits(s, "try-error")) next
  Am <- if (is.null(amat)) diag(K) else amat; Bm <- if (is.null(bmat)) diag(K) else bmat
  a <- c(seeds[mi], T0, K, p, det, mode, as.vector(t(Am)), as.vector(t(Bm)))
  add("sv_a", a, wsum(as.vector(t(s$A)))); add("sv_b", a, wsum(as.vector(t(s$B))))
  add("sv_ase", a, wsum(as.vector(t(s$Ase)))); add("sv_bse", a, wsum(as.vector(t(s$Bse))))
  add("sv_sigma", a, wsum(as.vector(t(s$Sigma.U)))); add("sv_iter", a, s$iter)
  if (!is.null(s$LR)) { add("sv_lr", a, s$LR$statistic); add("sv_lrp", a, s$LR$p.value); add("sv_lrdf", a, s$LR$parameter) }
  add("sv_irf0", c(a, H, 0), irfws(irf(s, n.ahead = H, boot = FALSE)$irf, H))
  add("sv_irf1", c(a, H, 1), irfws(irf(s, n.ahead = H, boot = FALSE, cumulative = TRUE)$irf, H))
  fe <- fevd(s, n.ahead = H); tot <- 0; pos <- 0
  for (i in seq_len(K)) for (n in 1:H) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + fe[[i]][n, j] * pos }
  add("sv_fevd", c(a, H), tot)
  # estmethod = "direct" (optim's Nelder-Mead): the mode is offset by 10; no hessian, so no standard errors
  sd <- try(suppressWarnings(do.call(SVAR, list(x = v, estmethod = "direct", Amat = amat, Bmat = bmat))), silent = TRUE)
  if (!inherits(sd, "try-error")) {
    ad <- a; ad[6] <- mode + 10
    add("sv_a", ad, wsum(as.vector(t(sd$A)))); add("sv_b", ad, wsum(as.vector(t(sd$B))))
    add("sv_sigma", ad, wsum(as.vector(t(sd$Sigma.U)))); add("sv_iter", ad, sd$iter)
    if (!is.null(sd$LR)) { add("sv_lr", ad, sd$LR$statistic); add("sv_lrp", ad, sd$LR$p.value) }
    add("sv_irf0", c(ad, H, 0), irfws(irf(sd, n.ahead = H, boot = FALSE)$irf, H))
    add("sv_fevd", c(ad, H), { fe <- fevd(sd, n.ahead = H); tot <- 0; pos <- 0
      for (i in seq_len(K)) for (n in 1:H) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + fe[[i]][n, j] * pos }; tot })
  }
  if (mi %% 2 == 1) {
    ir <- suppressWarnings(irf(s, n.ahead = H, boot = TRUE, runs = 30, ci = 0.9, seed = 11 + mi))
    b <- c(a, H, 30, 0.9, 11 + mi, 0)
    add("sv_bootlo", b, irfws(ir$Lower, H)); add("sv_boothi", b, irfws(ir$Upper, H))
  }
}
emit("vars_svar", "vars", list(cases))
