# laeken beyond the weighted statistics: gpg, weightedRate, eqSS, eqInc, calibWeights, the bootstrap variance of bootVar, the Pareto tail functions,
# minAMSE and the numbers of meanExcessPlot / paretoQPlot. Argument layouts (all numeric; counts first, then the vectors):
#   "gpg"    (method, n, inc[n], w[n], male[n])                               -> genderGap value
#   "wrate"  (n, threshold, inc[n], w[n])                                      -> weightedRate
#   "eqss"   (n, q, hid[n], age[n])                                            -> eqSS[q]
#   "eqinc"  (n, q, nhp, nhm, npp, npm, hid[n], hplus[n nhp], hminus[n nhm], pplus[n npp], pminus[n npm], eqss[n]) -> eqInc[q]
#   "calib"  (method, n, p, b0, b1, q, X[n p], d[n], totals[p])                -> q 0 sum(g), 1 sum(g * 1:n), 2 min(g), 3 max(g); method 0 raking 1 linear 2 logit
#   "boot"   (kind, p, n, nlev, calib, R, ciType, alpha, seed, naux, hasdesign, hascluster, q, inc[n], w[n], male[n], stratum[n], design[n], cluster[n],
#             aux[n naux], totals[naux], levels[nlev]); kind 0 gini 1 qsr 2 rmpg 3 arpr 4 gpg mean 5 gpg median; ns = 1 + nlev; q 0..ns-1 variance of statistic q,
#             ns + 2 s lower and ns + 2 s + 1 upper interval end; ciType 0 perc 1 norm 2 basic
#   "ptail"  (method, usek, k, x0, n, hasw, alpha, c1, c2, bias, q, x[n], w[n]); method 0 Hill 1 ISE 2 PDC 3 LS 4 moment 5 QQ 6 TM 7 WML residuals 8 WML probability;
#            q 0 theta 1 x0 2 k 3 outlier threshold 4 number of outliers 5 sum of outlier indices 6 index-weighted sum of tail indices
#   "pscale" (center, p1, p2, n, hasw, q, x[n], w[n])                          -> q 0 x0, 1 k
#   "fitp"   (seed, method, usek, k, x0, n, q, x[n])                           -> q 0 sum, 1 index-weighted sum of fitPareto(x)
#   "repl"   (seed, mode, k, alpha, n, q, x[n])                                -> mode 0 replaceTail, 1 replaceOut, 2 shrinkOut; q 0 sum, 1 index-weighted sum
#   "rw"     (hasw, method, n, p, k, alpha, q, x[n], w[n], X[n p])             -> reweightOut weights; q 0 sum, 1 index-weighted sum
#   "amse"   (n, bern, q, x[n])                                                -> q 0 kopt 1 x0 2 theta 3 MSEmin 4 rho
#   "mexp"   (n, hasw, nprobs, q, x[n], w[n], probs)                           -> mean excess points: q 0 sum(mu) 1 sum(me) 2 count
#   "pqy"    (n, hasw, q, x[n], w[n])                                          -> paretoQPlot y: q 0 sum, 1 index-weighted sum
suppressMessages(library(laeken))
weightedRate <- laeken:::weightedRate; rpareto <- laeken:::rpareto; qpareto <- laeken:::qpareto
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261201)
mkinc <- function(n) round(rlnorm(n, 10, 0.7) / 50) * 50
mkw <- function(n) round(runif(n, 0.5, 3), 3)
# gpg
for (rep in 1:6) {
  n <- sample(30:90, 1); inc <- mkinc(n); w <- mkw(n); male <- rbinom(n, 1, 0.5); if (sum(male) < 3 || sum(male) > n - 3) next
  g <- factor(ifelse(male == 1, "male", "female"), levels = c("female", "male"))
  for (m in 0:1) add("gpg", c(m, n, inc, w, male), gpg(inc, gender = g, method = c("mean", "median")[m + 1], weights = w)$value)
  add("wrate", c(n, 0.6 * median(inc), inc, w), weightedRate(inc, w, 0.6 * median(inc)))
}
# eqSS and eqInc
for (rep in 1:3) {
  nh <- sample(8:14, 1); sizes <- sample(1:5, nh, TRUE); hid <- rep(1:nh, sizes); n <- length(hid)
  age <- sample(0:80, n, TRUE); age[!duplicated(hid)] <- sample(18:80, nh, TRUE)
  s <- eqSS(hid, age)
  for (q in c(1, n)) add("eqss", c(n, q - 1, hid, age), s[q])
  hp <- matrix(round(runif(n * 2, 0, 5000)), n, 2); hm <- matrix(round(runif(n, 0, 800)), n, 1); hp[sample(n * 2, 3)] <- NA
  pp <- matrix(round(runif(n * 2, 0, 9000)), n, 2); pm <- matrix(round(runif(n * 2, 0, 700)), n, 2); pp[sample(n * 2, 2)] <- NA
  colnames(hp) <- c("a", "b"); colnames(hm) <- "c"; colnames(pp) <- c("d", "e"); colnames(pm) <- c("f", "g")
  ei <- eqInc(hid, as.data.frame(hp), as.data.frame(hm), as.data.frame(pp), as.data.frame(pm), s)
  for (q in c(1, 2, n)) add("eqinc", c(n, q - 1, 2, 1, 2, 2, hid, hp, hm, pp, pm, s), ei[q])
}
# calibWeights
for (rep in 1:9) {
  n <- sample(40:120, 1); p <- sample(2:4, 1)
  X <- cbind(1, matrix(rbinom(n * (p - 1), 1, 0.4) + 0, n, p - 1)); d <- mkw(n)
  totals <- colSums(X * d) * runif(p, 0.9, 1.1)
  m <- rep %% 3
  b <- c(0.3, 4)
  g <- tryCatch(suppressWarnings(calibWeights(X, d, totals, method = c("raking", "linear", "logit")[m + 1], bounds = b)), error = function(e) NULL)
  if (is.null(g)) next
  a <- c(m, n, p, b, 0, X, d, totals)
  for (q in 0:3) { a2 <- a; a2[6] <- q; add("calib", a2, c(sum(g), sum(g * seq_len(n)), min(g), max(g))[q + 1], rel = 1e-8, abs = 1e-9) }
}
# bootstrap variance
kinds <- c("gini", "qsr", "rmpg", "arpr", "gpgm", "gpgd")
for (rep in 1:24) {
  kind <- (rep - 1) %% 6; n <- sample(40:70, 1); R <- sample(c(30, 50), 1)
  inc <- mkinc(n); w <- mkw(n); male <- rbinom(n, 1, 0.5); if (sum(male) < 4 || sum(male) > n - 4) male[1:6] <- c(1, 0, 1, 0, 1, 0)
  g <- factor(ifelse(male == 1, "male", "female"), levels = c("female", "male"))
  pp <- if (kind == 3) sample(c(0.5, 0.6), 1) else 0.6
  nlev <- if (rep %% 4 == 1) 3 else 0
  stratum <- sample(1:3, n, TRUE); levels <- sort(unique(stratum)); if (nlev > 0) nlev <- length(levels)
  hasdesign <- rep %% 3 == 0; design <- if (hasdesign) rep(1:2, length.out = n)[sample(n)] else rep(1, n)
  hascluster <- rep %% 5 == 0; cluster <- if (hascluster) sort(sample(1:20, n, TRUE)) else rep(0, n)
  calib <- rep %% 2 == 0; naux <- 2; aux <- cbind(1, rbinom(n, 1, 0.5)); totals <- colSums(aux * w)
  ciType <- (rep - 1) %% 3; alpha <- sample(c(0.05, 0.1), 1); seed <- sample(1:1e6, 1)
  if (hasdesign && any(table(design) < 2)) next
  if (nlev > 0 && any(table(stratum) < 3)) next
  if (kind >= 4 && nlev > 0 && any(table(stratum, male) < 2)) next
  bd <- if (nlev > 0) stratum else NULL
  ind <- switch(kind + 1, gini(inc, w, breakdown = bd), qsr(inc, w, breakdown = bd), rmpg(inc, w, breakdown = bd), arpr(inc, w, p = pp, breakdown = bd),
                gpg(inc, gender = g, method = "mean", weights = w, breakdown = bd), gpg(inc, gender = g, method = "median", weights = w, breakdown = bd))
  v <- tryCatch(suppressWarnings(variance(inc, w, breakdown = bd, design = if (hasdesign) as.integer(design) else NULL, cluster = if (hascluster) as.integer(cluster) else NULL,
                  indicator = ind, X = if (calib) aux else NULL, R = R, bootType = if (calib) "calibrate" else "naive",
                  ciType = c("perc", "norm", "basic")[ciType + 1], alpha = alpha, seed = seed, gender = if (kind >= 4) g else NULL,
                  method = if (kind >= 4) c("mean", "median")[kind - 3] else NULL)), error = function(e) NULL)
  if (is.null(v)) next
  ns <- 1 + nlev
  vars <- if (nlev > 0) c(v$var, v$varByStratum$var) else v$var
  lo <- if (nlev > 0) c(v$ci[1], v$ciByStratum$lower) else v$ci[1]; hi <- if (nlev > 0) c(v$ci[2], v$ciByStratum$upper) else v$ci[2]
  a <- c(kind, pp, n, nlev, as.numeric(calib), R, ciType, alpha, seed, naux, as.numeric(hasdesign), as.numeric(hascluster), 0, inc, w, male, stratum, design, cluster, aux, totals, if (nlev > 0) levels)
  put <- function(q, val) { a2 <- a; a2[13] <- q; add("boot", a2, val, rel = 1e-8, abs = 1e-9) }
  for (s in seq_len(ns)) { put(s - 1, vars[s]); put(ns + 2 * (s - 1), lo[s]); put(ns + 2 * (s - 1) + 1, hi[s]) }
}
# Pareto tail
for (rep in 1:30) {
  n <- sample(c(60, 120, 250), 1); x <- round(rpareto(n, 1000, runif(1, 1.5, 3.5)) * runif(1, 0.8, 1.2)) + sample(0:20, n, TRUE)
  x[sample(n, n %/% 4)] <- round(runif(n %/% 4, 300, 1500))
  method <- (rep - 1) %% 9; k <- sample(seq(8, n %/% 3), 1); usek <- rep %% 2; x0 <- sort(x)[n - k] + 0.5
  hasw <- as.numeric(method <= 2 && rep %% 3 != 0); w <- round(runif(n, 0.5, 3), 3)
  alpha <- sample(c(0.01, 0.05), 1); c1 <- if (method == 8) 0.005 else if (method == 6) 0.05 else 2.5; c2 <- if (method == 8) 0.005 else 0.05; bias <- rep %% 4 != 0
  meth <- c("thetaHill", "thetaISE", "thetaPDC", "thetaLS", "thetaMoment", "thetaQQ", "thetaTM", "thetaWML", "thetaWML")[method + 1]
  extra <- switch(as.character(method), "6" = list(beta = c(c1, c2)), "7" = list(weight = "residuals", const = c1, bias = bias), "8" = list(weight = "probability", const = c(c1, c2), bias = bias), list())
  args <- c(list(x), if (usek) list(k = k) else list(x0 = x0), list(method = meth, alpha = alpha), extra, if (hasw) list(w = w))
  pt <- tryCatch(suppressWarnings(do.call(paretoTail, args)), error = function(e) NULL)
  if (is.null(pt)) next
  q <- qpareto(1 - alpha, pt$x0, pt$theta)
  a <- c(method, usek, k, x0, n, hasw, alpha, c1, c2, as.numeric(bias), 0, x, if (hasw) w else rep(1, n))
  put <- function(i, val) { a2 <- a; a2[11] <- i; add("ptail", a2, val, rel = 1e-7, abs = 1e-9) }
  put(0, pt$theta); put(1, pt$x0); put(2, pt$k); put(3, q); put(4, length(pt$out)); put(5, sum(pt$out)); put(6, sum(pt$tail * seq_along(pt$tail)))
}
for (rep in 1:8) {
  n <- sample(c(80, 200), 1); x <- round(rlnorm(n, 9, 1)); w <- mkw(n); hasw <- rep %% 2; ce <- c("mean", "median")[(rep %/% 2) %% 2 + 1]
  ps <- tryCatch(paretoScale(x, if (hasw) w else NULL, center = ce), error = function(e) NULL); if (is.null(ps)) next
  a <- c((rep %/% 2) %% 2, 0.97, 0.98, n, hasw, 0, x, w)
  for (i in 0:1) { a2 <- a; a2[6] <- i; add("pscale", a2, c(ps$x0, ps$k)[i + 1]) }
}
for (rep in 1:9) {
  n <- sample(c(60, 150), 1); x <- round(rpareto(n, 800, 2.2)); method <- (rep - 1) %% 9; k <- sample(8:(n %/% 4), 1); seed <- sample(1:1e6, 1)
  usek <- rep %% 2; x0 <- sort(x)[n - k] + 0.5
  meth <- c("thetaHill", "thetaISE", "thetaPDC", "thetaLS", "thetaMoment", "thetaQQ", "thetaTM", "thetaWML", "thetaWML")[method + 1]
  extra <- switch(as.character(method), "6" = list(beta = c(0.05, 0.05)), "7" = list(weight = "residuals", const = 2.5, bias = TRUE), "8" = list(weight = "probability", const = c(0.005, 0.005), bias = TRUE), list())
  set.seed(seed)
  r <- tryCatch(suppressWarnings(do.call(fitPareto, c(list(x), if (usek) list(k = k) else list(x0 = x0), list(method = meth), extra))), error = function(e) NULL); if (is.null(r)) next
  a <- c(seed, method, usek, k, x0, n, 0, x)
  for (i in 0:1) { a2 <- a; a2[7] <- i; add("fitp", a2, c(sum(r), sum(r * seq_along(r)))[i + 1], rel = 1e-7, abs = 1e-9) }
}
for (rep in 1:9) {
  n <- sample(c(80, 160), 1); x <- round(rpareto(n, 900, 2)); k <- sample(15:(n %/% 3), 1); alpha <- 0.05; seed <- sample(1:1e6, 1); mode <- (rep - 1) %% 3
  pt <- paretoTail(x, k = k, alpha = alpha); if (length(pt$out) == 0) next
  set.seed(seed)
  r <- switch(mode + 1, replaceTail(pt), replaceOut(pt), shrinkOut(pt))
  a <- c(seed, mode, k, alpha, n, 0, x)
  for (i in 0:1) { a2 <- a; a2[6] <- i; add("repl", a2, c(sum(r), sum(r * seq_along(r)))[i + 1], rel = 1e-7, abs = 1e-9) }
}
for (rep in 1:6) {
  n <- sample(c(80, 160), 1); x <- round(rpareto(n, 900, 2)); k <- sample(15:(n %/% 3), 1); alpha <- 0.05; hasw <- rep %% 2; w <- mkw(n)
  pt <- paretoTail(x, k = k, alpha = alpha, w = if (hasw) w else NULL, method = "thetaHill"); if (length(pt$out) == 0) next
  p <- 2; X <- cbind(1, rbinom(n, 1, 0.5)); m <- (rep %/% 2) %% 3
  r <- tryCatch(suppressWarnings(reweightOut(pt, X = X, method = c("raking", "linear", "logit")[m + 1], bounds = c(0.2, 5))), error = function(e) NULL); if (is.null(r)) next
  a <- c(hasw, m, n, p, k, alpha, 0, x, w, X)
  for (i in 0:1) { a2 <- a; a2[7] <- i; add("rw", a2, c(sum(r), sum(r * seq_along(r)))[i + 1], rel = 1e-7, abs = 1e-9) }
}
for (rep in 1:3) {
  n <- c(200, 260, 300)[rep]; x <- round(rpareto(n, 500, 2.5)); bern <- rep %% 2
  r <- tryCatch(suppressWarnings(minAMSE(x, weight = c("JASA", "Bernoulli")[bern + 1])), error = function(e) NULL); if (is.null(r)) next
  a <- c(n, bern, 0, x)
  for (i in 0:4) { a2 <- a; a2[3] <- i; add("amse", a2, c(r$kopt, r$x0, r$theta, r$MSEmin, r$rho)[i + 1], rel = 1e-7, abs = 1e-9) }
}
for (rep in 1:6) {
  n <- sample(c(40, 100), 1); x <- round(rlnorm(n, 9, 1)); w <- mkw(n); hasw <- rep %% 2
  probs <- if (rep > 3) c(0.5, 0.8, 0.9) else numeric(0); xx <- x
  ww <- if (hasw) w else NULL
  if (length(probs)) mu <- if (is.null(ww)) quantile(xx, probs, names = FALSE, type = 1) else weightedQuantile(xx, ww, probs)
  else { o <- order(xx); keep <- seq_len(n - sqrt(n)); mu <- unname(xx[o][keep]) }
  me <- sapply(mu, if (is.null(ww)) function(m) mean(xx[xx > m] - m) else function(m) { i <- xx > m; weighted.mean(xx[i] - m, ww[i]) })
  a <- c(n, hasw, length(probs), 0, x, w, probs)
  for (i in 0:2) { a2 <- a; a2[4] <- i; add("mexp", a2, c(sum(mu), sum(me), length(mu))[i + 1]) }
  o <- order(xx); y <- if (is.null(ww)) -log((n:1) / (n + 1)) else { cw <- cumsum(ww[o]); -log(1 - cw / (cw[n] * (n + 1) / n)) }
  a <- c(n, hasw, 0, x, w)
  for (i in 0:1) { a2 <- a; a2[3] <- i; add("pqy", a2, c(sum(y), sum(y * seq_along(y)))[i + 1]) }
}
emit("laeken_ext", "laeken", list(cases))
