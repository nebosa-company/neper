# vars on a cointegrated system: vec2var (the lag matrices, deterministic coefficients, residuals, irf with bootstrap bands, fevd, predict and the residual tests)
# and SVEC (short- and long-run restrictions by scoring, its irf with bootstrap bands, and fevd).
#   The data: e = rnorm(T0 K) column-major, y = cumsum of each column, then y[, 2] = y[, 1] + 0.5 e[, 2] (so r = 1).
#   args: (seed, T0, K, lag, ecdet, spec, season, r, extra...) with ecdet 0 none 1 const 2 trend and spec 0 longrun 1 transitory
suppressMessages(library(vars))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
H <- 6
gen <- function(seed, T0, K) {
  set.seed(seed)
  e <- matrix(rnorm(T0 * K), T0, K)
  y <- apply(e, 2, cumsum)
  y[, 2] <- y[, 1] + 0.5 * e[, 2]
  colnames(y) <- paste0("s", 1:K)
  y
}
wsum <- function(m) sum(as.vector(m) * seq_len(length(m)))
irfws <- function(ir, h) { tot <- 0; pos <- 0; for (imp in names(ir)) for (i in 0:h) for (j in seq_len(ncol(ir[[imp]]))) { pos <- pos + 1; tot <- tot + ir[[imp]][i + 1, j] * pos }; tot }
ecs <- c("none", "const", "trend"); sps <- c("longrun", "transitory")
mkjo <- function(y, lag, ecdet, spec, season) {
  a <- list(x = y, ecdet = ecs[ecdet + 1], K = lag, spec = sps[spec + 1])
  if (season > 0) a$season <- season
  do.call(ca.jo, a)
}
cfgs <- list(c(601, 120, 2, 2, 1, 0, 0, 1), c(602, 140, 3, 2, 0, 0, 0, 1), c(603, 150, 3, 3, 2, 1, 0, 1), c(604, 130, 2, 3, 0, 1, 4, 1),
             c(605, 160, 3, 2, 1, 1, 0, 2), c(606, 140, 3, 3, 1, 0, 4, 1), c(607, 120, 2, 2, 2, 0, 0, 1), c(608, 150, 3, 2, 2, 0, 4, 2))
for (cf in cfgs) {
  seed <- cf[1]; T0 <- cf[2]; K <- cf[3]; lag <- cf[4]; ecdet <- cf[5]; spec <- cf[6]; season <- cf[7]; r <- cf[8]
  y <- gen(seed, T0, K)
  jo <- mkjo(y, lag, ecdet, spec, season)
  v <- vec2var(jo, r = r)
  a <- cf
  add("v2_a", a, wsum(unlist(lapply(v$A, function(m) as.vector(t(m))))))
  add("v2_det", a, wsum(as.vector(t(v$deterministic))))
  add("v2_resid", a, wsum(as.vector(t(resid(v)))))
  for (b in 0:3) add(paste0("v2_irf", b), c(a, H, b), irfws(irf(v, n.ahead = H, ortho = (b %% 2) == 1, cumulative = b >= 2, boot = FALSE)$irf, H))
  fe <- fevd(v, n.ahead = H); tot <- 0; pos <- 0
  for (i in seq_len(K)) for (n in 1:H) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + fe[[i]][n, j] * pos }
  add("v2_fevd", c(a, H), tot)
  pr <- predict(v, n.ahead = H, ci = 0.9)$fcst
  for (cc in c(1, 4)) add(c("v2_fcst", "", "", "v2_ci")[cc], c(a, 0.9), sum(unlist(lapply(pr, function(m) as.vector(m[, cc]))) * seq_len(K * H)))
  lp <- 8; lb <- 3
  st <- serial.test(v, lags.pt = lp, type = "PT.asymptotic")$serial; add("v2_pt_stat", c(a, lp), st$statistic); add("v2_pt_df", c(a, lp), st$parameter); add("v2_pt_p", c(a, lp), st$p.value)
  st <- serial.test(v, lags.pt = lp, type = "PT.adjusted")$serial; add("v2_pta_stat", c(a, lp), st$statistic)
  st <- serial.test(v, lags.bg = lb, type = "BG")$serial; add("v2_bg_stat", c(a, lb), st$statistic); add("v2_bg_p", c(a, lb), st$p.value)
  st <- serial.test(v, lags.bg = lb, type = "ES")$serial; add("v2_es_stat", c(a, lb), st$statistic); add("v2_es_p", c(a, lb), st$p.value)
  ar <- arch.test(v, lags.multi = 3); add("v2_archm_stat", c(a, 3), ar$arch.mul$statistic); add("v2_archm_p", c(a, 3), ar$arch.mul$p.value)
  nt <- normality.test(v); add("v2_jb_stat", a, nt$jb.mul$JB$statistic); add("v2_jb_p", a, nt$jb.mul$JB$p.value)
}
# bootstrap bands of irf(vec2var)
for (cf in list(c(601, 120, 2, 2, 1, 0, 0, 1, 30, 0.9, 41, 1, 0), c(602, 140, 3, 2, 0, 0, 0, 1, 25, 0.95, 42, 0, 1), c(604, 130, 2, 3, 0, 1, 4, 1, 20, 0.9, 43, 1, 1))) {
  y <- gen(cf[1], cf[2], cf[3]); jo <- mkjo(y, cf[4], cf[5], cf[6], cf[7]); v <- vec2var(jo, r = cf[8])
  ir <- irf(v, n.ahead = H, ortho = cf[12] == 1, cumulative = cf[13] == 1, boot = TRUE, runs = cf[9], ci = cf[10], seed = cf[11])
  add("v2_bootlo", c(cf, H), irfws(ir$Lower, H)); add("v2_boothi", c(cf, H), irfws(ir$Upper, H))
}
# SVEC: (seed, T0, K, lag, ecdet, spec, season, r, start seed, LR K*K row-major with NA free (0 restricted), SR K*K)
mat <- function(K, zeros) { m <- matrix(NA, K, K); for (z in zeros) m[z[1], z[2]] <- 0; m }
svs <- list(
  list(c(601, 150, 2, 2, 1, 0, 0, 1), list(c(1, 2)), list()),
  list(c(609, 150, 2, 2, 0, 0, 0, 1), list(c(1, 2)), list(c(2, 2))),
  list(c(602, 150, 3, 2, 0, 0, 0, 1), list(c(1, 3), c(2, 3), c(3, 3), c(1, 2)), list()),
  list(c(610, 150, 3, 2, 0, 0, 0, 1), list(c(1, 3), c(2, 3), c(3, 3), c(1, 2)), list(c(3, 1))),
  list(c(611, 160, 3, 3, 1, 1, 0, 1), list(c(1, 3), c(2, 3), c(3, 3), c(2, 2)), list(c(3, 2))),
  list(c(612, 150, 3, 2, 2, 0, 0, 1), list(c(1, 3), c(2, 3), c(3, 3), c(1, 2)), list(c(2, 1))))
k <- 0
for (sv in svs) {
  k <- k + 1; cf <- sv[[1]]; K <- cf[3]; r <- cf[8]
  LR <- mat(K, sv[[2]]); SR <- mat(K, sv[[3]])
  y <- gen(cf[1], cf[2], K); jo <- mkjo(y, cf[4], cf[5], cf[6], cf[7])
  ss <- 700 + k
  set.seed(ss)
  s <- try(suppressWarnings(do.call(SVEC, list(x = jo, LR = LR, SR = SR, r = r, lrtest = TRUE))), silent = TRUE)
  if (inherits(s, "try-error")) next
  a <- c(cf, ss, as.vector(t(LR)), as.vector(t(SR)))
  add("sv_sr", a, wsum(as.vector(t(s$SR)))); add("sv_lr", a, wsum(as.vector(t(s$LR))))
  add("sv_sigma", a, wsum(as.vector(t(s$Sigma.U)))); add("sv_nres", a, wsum(s$Restrictions)); add("sv_iter", a, s$iter)
  if (!is.null(s$LRover)) { add("sv_lrstat", a, s$LRover$statistic); add("sv_lrp", a, s$LRover$p.value); add("sv_lrdf", a, s$LRover$parameter) }
  add("sv_irf0", c(a, H, 0), irfws(irf(s, n.ahead = H, boot = FALSE)$irf, H))
  add("sv_irf1", c(a, H, 1), irfws(irf(s, n.ahead = H, boot = FALSE, cumulative = TRUE)$irf, H))
  fe <- fevd(s, n.ahead = H); tot <- 0; pos <- 0
  for (i in seq_len(K)) for (n in 1:H) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + fe[[i]][n, j] * pos }
  add("sv_fevd", c(a, H), tot)
  if (k %% 2 == 1) {
    ir <- suppressWarnings(irf(s, n.ahead = H, boot = TRUE, runs = 15, ci = 0.9, seed = 50 + k))
    b <- c(a, H, 15, 0.9, 50 + k, 0)
    add("sv_bootlo", b, irfws(ir$Lower, H)); add("sv_boothi", b, irfws(ir$Upper, H))
  }
}
emit("vars_vec", c("vars", "urca"), list(cases))
