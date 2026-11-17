# vars: causality (Granger, bootstrapped Granger, instantaneous), serial.test (PT.asymptotic, PT.adjusted, BG, ES), arch.test, normality.test, restrict (ser and manual),
# BQ, and the model outputs (coefficients, irf, predict, fevd) of a restricted VAR.
#   Every case rebuilds its data from the seed as in vars_core. args: (seed, T0, K, p, det, season, nexo, slope, rmode, rpar, extra...)
#   rmode 0 unrestricted, 1 restrict(method = "ser", thresh = rpar), 2 restrict(method = "manual") keeping a coefficient unless (row + column) %% 3 == rpar
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
nm <- function(K) paste0("s", 1:K)
causes <- function(K) if (K == 2) c(1, 2) else c(1, 2, 5, 6)
cause_names <- function(K, mask) nm(K)[bitwAnd(mask, 2^(0:(K - 1))) > 0]
cfgs <- list(
  c(301, 100, 2, 2, 1, 0, 0, 0, 0, 0), c(302, 110, 3, 2, 1, 0, 0, 0, 0, 0), c(303, 90, 2, 1, 3, 0, 0, 0.02, 0, 0), c(304, 120, 3, 3, 0, 0, 0, 0, 0, 0),
  c(305, 100, 2, 2, 1, 4, 1, 0, 0, 0), c(306, 130, 3, 1, 2, 0, 2, 0.01, 0, 0), c(307, 100, 2, 2, 1, 0, 0, 0, 1, 1.2), c(308, 140, 3, 2, 1, 0, 0, 0, 1, 1.0),
  c(309, 100, 2, 2, 1, 0, 0, 0, 2, 0), c(310, 120, 3, 1, 1, 0, 0, 0, 2, 1), c(311, 110, 2, 3, 3, 0, 1, 0, 2, 2), c(312, 150, 3, 2, 3, 0, 0, 0.02, 1, 1.5))
for (cf in cfgs) {
  seed <- cf[1]; T0 <- cf[2]; K <- cf[3]; p <- cf[4]; det <- cf[5]; season <- cf[6]; nexo <- cf[7]; slope <- cf[8]; rmode <- cf[9]; rpar <- cf[10]
  d <- gen(seed, T0, K, nexo, slope)
  v <- mk(d, p, det, season)
  if (rmode == 1) v <- try(restrict(v, method = "ser", thresh = rpar), silent = TRUE)
  if (rmode == 2) {
    nz <- ncol(v$datamat) - K
    rm <- matrix(1, K, nz); for (i in 1:K) for (c in 1:nz) if ((i + c) %% 3 == rpar) rm[i, c] <- 0
    if (any(rowSums(rm) == 0)) next
    v <- restrict(v, method = "manual", resmat = rm)
  }
  if (inherits(v, "try-error")) next
  a <- c(seed, T0, K, p, det, season, nexo, slope, rmode, rpar)
  add("coef", a, wsum(as.vector(t(Bcoef(v)))))
  add("resid", a, wsum(as.vector(t(resid(v)))))
  ir <- irf(v, n.ahead = H, ortho = FALSE, boot = FALSE)$irf; add("irf0", a, irfws(ir, H))
  ir <- irf(v, n.ahead = H, ortho = TRUE, cumulative = TRUE, boot = FALSE)$irf; add("irf3", a, irfws(ir, H))
  fe <- fevd(v, n.ahead = H); tot <- 0; pos <- 0
  for (i in seq_len(K)) for (n in 1:H) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + fe[[i]][n, j] * pos }
  add("fevd", a, tot)
  pr <- predict(v, n.ahead = H, ci = 0.95, dumvar = d$exof)$fcst
  add("fcst", a, sum(unlist(lapply(pr, function(m) as.vector(m[, 1]))) * seq_len(K * H)))
  add("ci", a, sum(unlist(lapply(pr, function(m) as.vector(m[, 4]))) * seq_len(K * H)))
  for (mk_ in causes(K)) {
    cs <- suppressWarnings(causality(v, cause = cause_names(K, mk_)))
    b <- c(a, mk_)
    add("g_f", b, cs$Granger$statistic); add("g_p", b, cs$Granger$p.value); add("g_df1", b, cs$Granger$parameter[1]); add("g_df2", b, cs$Granger$parameter[2])
    add("i_chi", b, cs$Instant$statistic); add("i_df", b, cs$Instant$parameter); add("i_p", b, cs$Instant$p.value)
  }
  mk_ <- causes(K)[1]; set.seed(seed + 7)
  cb <- suppressWarnings(causality(v, cause = cause_names(K, mk_), boot = TRUE, boot.runs = 60))
  add("g_pboot", c(a, mk_, 60, seed + 7), cb$Granger$p.value)
  lp <- 8
  st <- serial.test(v, lags.pt = lp, type = "PT.asymptotic")$serial; add("pt_stat", c(a, lp), st$statistic); add("pt_df", c(a, lp), st$parameter); add("pt_p", c(a, lp), st$p.value)
  st <- serial.test(v, lags.pt = lp, type = "PT.adjusted")$serial; add("pta_stat", c(a, lp), st$statistic); add("pta_p", c(a, lp), st$p.value)
  lb <- 3
  st <- serial.test(v, lags.bg = lb, type = "BG")$serial; add("bg_stat", c(a, lb), st$statistic); add("bg_df", c(a, lb), st$parameter); add("bg_p", c(a, lb), st$p.value)
  st <- serial.test(v, lags.bg = lb, type = "ES")$serial; add("es_stat", c(a, lb), st$statistic); add("es_df2", c(a, lb), st$parameter[2]); add("es_p", c(a, lb), st$p.value)
  la <- 3
  ar <- arch.test(v, lags.single = 4, lags.multi = la, multivariate.only = FALSE)
  add("archm_stat", c(a, la), ar$arch.mul$statistic); add("archm_df", c(a, la), ar$arch.mul$parameter); add("archm_p", c(a, la), ar$arch.mul$p.value)
  for (e in 1:K) { add("archu_stat", c(a, 4, e), ar$arch.uni[[e]]$statistic); add("archu_p", c(a, 4, e), ar$arch.uni[[e]]$p.value) }
  nt <- normality.test(v, multivariate.only = FALSE)
  add("jb_stat", a, nt$jb.mul$JB$statistic); add("jb_p", a, nt$jb.mul$JB$p.value); add("sk_stat", a, nt$jb.mul$Skewness$statistic); add("ku_stat", a, nt$jb.mul$Kurtosis$statistic)
  add("ku_p", a, nt$jb.mul$Kurtosis$p.value)
  for (e in 1:K) { add("jbu_stat", c(a, e), nt$jb.uni[[e]]$statistic); add("jbu_p", c(a, e), nt$jb.uni[[e]]$p.value) }
}
# restrict(ser): the coefficients after dropping, a thresh sweep
for (thr in c(0.5, 1, 1.645, 2)) {
  d <- gen(330, 150, 3, 0, 0); v <- mk(d, 2, 1, 0)
  r <- try(restrict(v, method = "ser", thresh = thr), silent = TRUE)
  if (!inherits(r, "try-error")) add("coef", c(330, 150, 3, 2, 1, 0, 0, 0, 1, thr), wsum(as.vector(t(Bcoef(r)))))
}
# BQ
for (cf in list(c(340, 120, 2, 2, 1, 0, 0, 0), c(341, 150, 3, 1, 1, 0, 0, 0), c(342, 130, 3, 2, 3, 0, 0, 0.01), c(343, 110, 2, 3, 0, 0, 0, 0))) {
  d <- gen(cf[1], cf[2], cf[3], 0, cf[8]); v <- mk(d, cf[4], cf[5], cf[6]); K <- cf[3]
  bq <- BQ(v)
  add("bq_lrim", cf, wsum(as.vector(t(bq$LRIM)))); add("bq_b", cf, wsum(as.vector(t(bq$B))))
  add("bq_sigma", cf, wsum(as.vector(t(bq$Sigma.U))))
  add("bq_irf", cf, irfws(irf(bq, n.ahead = H, boot = FALSE)$irf, H))
}
emit("vars_chk", "vars", list(cases))
