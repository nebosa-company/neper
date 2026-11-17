# vars (beyond const-only): VAR with none/const/trend/both, seasonal dummies and exogenous regressors, VARselect, roots, predict, irf with bootstrap bands, fevd.
#   Every case rebuilds its data from the seed: y_t = A y_{t-1} + rnorm(K) + slope t with A = runif(K K, -.3, .3) (column-major), then exo = rnorm(T0 nexo),
#   then the future exogenous rows rnorm(H nexo). args: (seed, T0, K, p, det, season, nexo, slope, extra...), det 0 none 1 const 2 trend 3 both.
#   Weighted sums use the position as the weight, so a transposed or shifted result cannot agree.
suppressMessages(library(vars))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
H <- 6
gen <- function(seed, T0, K, nexo, slope) {
  set.seed(seed)
  A <- matrix(runif(K * K, -0.3, 0.3), K, K)
  y <- matrix(0, T0, K)
  for (t in 2:T0) y[t, ] <- A %*% y[t - 1, ] + rnorm(K) + slope * t
  colnames(y) <- paste0("s", 1:K)
  exo <- NULL; exof <- NULL
  if (nexo > 0) {
    exo <- matrix(rnorm(T0 * nexo), T0, nexo); colnames(exo) <- paste0("e", 1:nexo)
    exof <- matrix(rnorm(H * nexo), H, nexo); colnames(exof) <- colnames(exo)
  }
  list(y = y, exo = exo, exof = exof)
}
wsum <- function(m) sum(as.vector(m) * seq_len(length(m)))
types <- c("none", "const", "trend", "both")
mk <- function(d, p, det, season) {
  a <- list(y = d$y, p = p, type = types[det + 1])
  if (season > 0) a$season <- season
  if (!is.null(d$exo)) a$exogen <- d$exo
  do.call(VAR, a)
}
irfws <- function(ir, h) { tot <- 0; pos <- 0; for (imp in names(ir)) for (i in 0:h) for (j in seq_len(ncol(ir[[imp]]))) { pos <- pos + 1; tot <- tot + ir[[imp]][i + 1, j] * pos }; tot }
cfgs <- list(
  c(101, 80, 2, 1, 1, 0, 0, 0), c(102, 90, 3, 2, 1, 0, 0, 0), c(103, 100, 2, 2, 0, 0, 0, 0), c(104, 70, 2, 1, 2, 0, 0, 0.02),
  c(105, 85, 3, 2, 3, 0, 0, 0.02), c(106, 96, 2, 2, 1, 4, 0, 0), c(107, 120, 3, 3, 1, 12, 0, 0), c(108, 80, 2, 2, 1, 0, 1, 0),
  c(109, 90, 3, 1, 3, 0, 2, 0.01), c(110, 100, 2, 3, 0, 0, 2, 0), c(111, 88, 2, 2, 3, 4, 1, 0), c(112, 110, 3, 2, 2, 0, 1, 0.02),
  c(113, 64, 2, 1, 1, 0, 0, 0), c(114, 75, 3, 1, 1, 0, 0, 0), c(115, 140, 4, 2, 3, 0, 1, 0.01), c(116, 150, 5, 1, 1, 4, 0, 0), c(117, 100, 2, 5, 3, 12, 2, 0), c(118, 90, 4, 3, 0, 0, 0, 0))
for (cf in cfgs) {
  seed <- cf[1]; T0 <- cf[2]; K <- cf[3]; p <- cf[4]; det <- cf[5]; season <- cf[6]; nexo <- cf[7]; slope <- cf[8]
  d <- gen(seed, T0, K, nexo, slope)
  v <- mk(d, p, det, season)
  a <- c(seed, T0, K, p, det, season, nexo, slope)
  B <- Bcoef(v)
  add("coef", a, wsum(as.vector(t(B))))
  add("sigma", a, wsum(summary(v)$covres))
  add("resid", a, wsum(as.vector(t(resid(v)))))
  add("roots", a, wsum(roots(v)))
  add("loglik", a, as.numeric(logLik(v)))
  for (e in 1:K) {
    s <- summary(v)$varresult[[e]]; cf <- coef(s); ae <- c(a, e)
    add("sm_est", ae, wsum(cf[, 1])); add("sm_se", ae, wsum(cf[, 2])); add("sm_t", ae, wsum(cf[, 3])); add("sm_p", ae, wsum(cf[, 4]))
    add("sm_sigma", ae, s$sigma); add("sm_r2", ae, s$r.squared); add("sm_adj", ae, s$adj.r.squared)
    add("sm_f", ae, s$fstatistic[1]); add("sm_fp", ae, pf(s$fstatistic[1], s$fstatistic[2], s$fstatistic[3], lower.tail = FALSE))
  }
  lm_ <- p + 2
  vs <- VARselect(d$y, lag.max = lm_, type = types[det + 1], season = if (season > 0) season else NULL, exogen = d$exo)
  for (c in 1:4) add(c("aic", "hq", "sc", "fpe")[c], c(a, lm_), wsum(vs$criteria[c, ]))
  add("selection", c(a, lm_), wsum(vs$selection))
  pr <- predict(v, n.ahead = H, ci = 0.9, dumvar = d$exof)$fcst
  for (cc in 1:4) add(c("fcst", "lower", "upper", "ci")[cc], c(a, 0.9), sum(unlist(lapply(pr, function(m) as.vector(m[, cc]))) * seq_len(K * H)))
  for (b in 0:3) add(paste0("irf", b), c(a, H, b), irfws(irf(v, n.ahead = H, ortho = (b %% 2) == 1, cumulative = b >= 2, boot = FALSE)$irf, H))
  fe <- fevd(v, n.ahead = H); tot <- 0; pos <- 0
  for (i in seq_len(K)) for (n in 1:H) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + fe[[i]][n, j] * pos }
  add("fevd", c(a, H), tot)
}
# the bootstrap bands: runs, ci, seed, ortho, cumulative
bcfgs <- list(c(201, 80, 2, 1, 1, 0, 0, 0, 100, 0.95, 77, 1, 0), c(202, 90, 3, 2, 1, 0, 0, 0, 60, 0.9, 5, 0, 0), c(203, 100, 2, 2, 3, 0, 1, 0.01, 50, 0.8, 12345, 1, 1),
              c(204, 96, 2, 2, 1, 4, 0, 0, 40, 0.95, 31, 0, 1), c(205, 70, 3, 1, 0, 0, 0, 0, 100, 0.95, 2026, 1, 0))
for (cf in bcfgs) {
  seed <- cf[1]; T0 <- cf[2]; K <- cf[3]; p <- cf[4]; det <- cf[5]; season <- cf[6]; nexo <- cf[7]; slope <- cf[8]
  runs <- cf[9]; ci <- cf[10]; bs <- cf[11]; ortho <- cf[12] == 1; cum <- cf[13] == 1
  d <- gen(seed, T0, K, nexo, slope); v <- mk(d, p, det, season)
  ir <- irf(v, n.ahead = H, ortho = ortho, cumulative = cum, boot = TRUE, runs = runs, ci = ci, seed = bs)
  a <- c(seed, T0, K, p, det, season, nexo, slope, H, runs, ci, bs, cf[12], cf[13])
  add("bootlo", a, irfws(ir$Lower, H)); add("boothi", a, irfws(ir$Upper, H))
}
emit("vars_core", "vars", list(cases))
