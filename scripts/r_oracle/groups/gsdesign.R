# gsDesign: alpha spending functions.
#   args: (kind, alpha, t, p1, p2)   fn "spend"
#   kind 0 sfHSD 1 sfPower 2 sfExponential 3 sfLogistic 4 sfNormal 5 sfCauchy 6 sfExtremeValue 7 sfBetaDist 8 sfLDOF 9 sfLDPocock
suppressMessages(library(gsDesign))
cases <- list()
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("spend", args, want, rel = 1e-9, abs = 1e-14)
set.seed(20261224)
for (rep in 1:12) {
  alpha <- c(0.025, 0.05, 0.0125, 0.1)[rep %% 4 + 1]
  for (t in c(0.05, 0.2, 0.5, 0.75, 0.99, 1)) {
    g <- c(-4, -2, 1, 3, 5)[rep %% 5 + 1]; rho <- c(0.5, 1, 2, 3)[rep %% 4 + 1]; nu <- c(0.2, 0.5, 1)[rep %% 3 + 1]
    a <- runif(1, -1, 1); b <- runif(1, 0.4, 2.5)
    add(c(0, alpha, t, g, 0), sfHSD(alpha, t, g)$spend)
    add(c(1, alpha, t, rho, 0), sfPower(alpha, t, rho)$spend)
    add(c(2, alpha, t, nu, 0), sfExponential(alpha, t, nu)$spend)
    add(c(3, alpha, t, a, b), sfLogistic(alpha, t, c(a, b))$spend)
    add(c(4, alpha, t, a, b), sfNormal(alpha, t, c(a, b))$spend)
    add(c(5, alpha, t, a, b), sfCauchy(alpha, t, c(a, b))$spend)
    add(c(6, alpha, t, a, b), sfExtremeValue(alpha, t, c(a, b))$spend)
    add(c(7, alpha, t, abs(a) + 0.3, b), sfBetaDist(alpha, t, c(abs(a) + 0.3, b))$spend)
    add(c(8, alpha, t, rho, 0), sfLDOF(alpha, t, rho)$spend)
    add(c(9, alpha, t, 0, 0), sfLDPocock(alpha, t)$spend)
  }
}

# ---- gsDesign(): fn "design", args (out, k, tt, alpha, beta, delta, nfix, upk, up1, up2, lok, lo1, lo2, tol, r, overrun, maxn, hasNI, astar, timing[k], nI[k] if hasNI)
#   out = field * 100 + index: 1 upper bound, 2 lower bound, 3 n.I, 4/5 upper prob at theta 0 / delta, 6/7 lower prob, 8/9 en, 10 delta, 11 n.fix,
#   12 upper spend, 13 lower spend, 14 final k.   upk/lok 0-9 as in "spend"; upk 100 OF, 101 Pocock, 102 WT
sfs <- list(sfHSD, sfPower, sfExponential, sfLogistic, sfNormal, sfCauchy, sfExtremeValue, sfBetaDist, sfLDOF, sfLDPocock)
sfpar <- function(kind, p1, p2) if (kind %in% 3:7) c(p1, p2) else p1
design_cases <- function(k, tt, alpha, beta, delta, nfix, upk, up1, up2, lok, lo1, lo2, timing, nI = NULL, maxn = 0, tol = 1e-6, r = 18, overrun = 0, astar = 0) {
  sfu <- if (upk >= 100) c("OF", "Pocock", "WT")[upk - 99] else sfs[[upk + 1]]
  upar <- if (upk >= 100) up1 else sfpar(upk, up1, up2)
  sfl <- sfs[[lok + 1]]
  x <- tryCatch(gsDesign(k = k, test.type = tt, alpha = alpha, beta = beta, delta = delta, n.fix = nfix, timing = timing,
                         sfu = sfu, sfupar = upar, sfl = sfl, sflpar = sfpar(lok, lo1, lo2), tol = tol, r = r,
                         n.I = if (is.null(nI)) 0 else nI, maxn.IPlan = maxn, overrun = overrun, astar = astar),
                error = function(e) { message("skip: ", conditionMessage(e)); NULL })
  if (is.null(x)) return(invisible())
  pre <- c(k, tt, alpha, beta, delta, nfix, upk, up1, up2, lok, lo1, lo2, tol, r, overrun, maxn, !is.null(nI), astar, timing, nI)
  kk <- x$k
  add1 <- function(f, i, v) if (is.finite(v)) cases[[length(cases) + 1]] <<- case("design", c(f * 100 + i - 1, pre), v, rel = 1e-9, abs = 1e-12)
  for (i in seq_len(kk)) {
    add1(1, i, x$upper$bound[i]); add1(3, i, x$n.I[i]); add1(4, i, x$upper$prob[i, 1]); add1(5, i, x$upper$prob[i, 2]); add1(12, i, x$upper$spend[i])
    if (tt >= 2) { add1(2, i, x$lower$bound[i]); add1(6, i, x$lower$prob[i, 1]); add1(7, i, x$lower$prob[i, 2]); add1(13, i, x$lower$spend[i]) }
  }
  add1(8, 1, x$en[1]); add1(9, 1, x$en[2]); add1(10, 1, x$delta); add1(11, 1, x$n.fix); add1(14, 1, kk)
  invisible(x)
}
tm <- function(k) (1:k) / k
for (k in c(2, 3, 4, 5)) for (tt in c(1, 2, 3, 4)) {
  design_cases(k, tt, 0.025, 0.1, 0, 1, 9, 1, 0, 0, -2, 0, tm(k))
}
design_cases(3, 4, 0.025, 0.1, 0, 1, 0, -4, 0, 0, -2, 0, tm(3))
design_cases(4, 4, 0.05, 0.2, 0, 1, 0, -3, 0, 0, 1, 0, c(0.2, 0.5, 0.8, 1))
design_cases(3, 4, 0.025, 0.15, 0, 1, 1, 3, 0, 1, 2, 0, c(0.3, 0.6, 1))
design_cases(3, 4, 0.025, 0.1, 0, 100, 9, 1, 0, 9, 1, 0, c(0.4, 0.7, 1))
design_cases(5, 4, 0.025, 0.1, 0.35, 1, 8, 1, 0, 0, -2, 0, tm(5))
design_cases(3, 4, 0.025, 0.1, 0, 1, 2, 0.5, 0, 0, -1, 0, tm(3))
design_cases(3, 3, 0.025, 0.1, 0, 1, 0, -4, 0, 0, -2, 0, tm(3))
design_cases(4, 3, 0.05, 0.2, 0, 1, 8, 1, 0, 0, 1, 0, c(0.25, 0.5, 0.75, 1))
design_cases(3, 3, 0.025, 0.1, 0.4, 1, 9, 1, 0, 8, 1, 0, c(0.3, 0.7, 1))
design_cases(2, 2, 0.025, 0.1, 0, 1, 0, -4, 0, 0, -2, 0, c(0.5, 1))
design_cases(4, 2, 0.05, 0.1, 0, 1, 8, 1, 0, 0, -2, 0, c(0.25, 0.5, 0.75, 1))
design_cases(3, 2, 0.025, 0.2, 0, 1, 0, -2, 0, 0, -2, 0, c(0.3, 0.6, 1))
design_cases(3, 1, 0.025, 0.1, 0, 1, 0, -4, 0, 0, -2, 0, c(0.3, 0.6, 1))
design_cases(4, 1, 0.05, 0.2, 0, 1, 9, 1, 0, 0, -2, 0, c(0.25, 0.5, 0.75, 1))
design_cases(3, 1, 0.025, 0.1, 0.25, 1, 8, 1, 0, 0, -2, 0, tm(3))
# test.type 5: binding lower bound spending astar; the default astar = 1 - alpha ends with a[k] = b[k]
design_cases(3, 5, 0.025, 0.1, 0, 1, 9, 1, 0, 0, -2, 0, tm(3))
design_cases(4, 5, 0.025, 0.1, 0, 1, 8, 1, 0, 0, -2, 0, c(0.25, 0.5, 0.75, 1), astar = 0.3)
design_cases(3, 5, 0.05, 0.2, 0.35, 1, 0, -4, 0, 1, 2, 0, c(0.3, 0.6, 1), astar = 0.5)
design_cases(3, 5, 0.025, 0.1, 0.3, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(40, 80, 120))
design_cases(3, 5, 0.025, 0.1, 0.3, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(40, 80, 120), astar = 0.4)
# Wang-Tsiatis bounds
for (k in c(3, 4)) for (tt in c(1, 2)) for (u in c(100, 101)) design_cases(k, tt, 0.025, 0.1, 0, 1, u, 0, 0, 0, -2, 0, tm(k))
design_cases(3, 1, 0.025, 0.1, 0, 1, 102, 0.25, 0, 0, -2, 0, c(0.3, 0.6, 1))
design_cases(3, 2, 0.025, 0.1, 0, 1, 102, 0.25, 0, 0, -2, 0, c(0.3, 0.6, 1))
design_cases(4, 2, 0.05, 0.2, 0, 1, 102, -0.1, 0, 0, -2, 0, c(0.2, 0.5, 0.8, 1))
# information given (n.I): bounds at fixed analyses, with and without maxn.IPlan
for (tt in 1:4) {
  design_cases(3, tt, 0.025, 0.1, 0.3, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(40, 80, 120))
  design_cases(4, tt, 0.05, 0.2, 0.25, 1, 0, -4, 0, 0, -2, 0, tm(4), nI = c(30, 60, 90, 120))
  design_cases(3, tt, 0.025, 0.1, 0.3, 1, 8, 1, 0, 0, -2, 0, tm(3), nI = c(40, 90, 150), maxn = 160)
}
design_cases(3, 3, 0.025, 0.1, 0.3, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(70, 130, 200))
design_cases(3, 3, 0.025, 0.1, 0.5, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(30, 50, 80))
# the analysis count falls when the lower bound has spent its beta early (type 3, n.I given)
design_cases(3, 3, 0.025, 0.1, 0.6, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(30, 60, 90))
design_cases(3, 3, 0.025, 0.1, 0.4, 1, 9, 1, 0, 0, -2, 0, tm(3), nI = c(66.667, 133.333, 200))
design_cases(4, 3, 0.025, 0.1, 0.6, 1, 0, -4, 0, 0, 1, 0, tm(4), nI = c(30, 60, 90, 120))
design_cases(4, 3, 0.025, 0.1, 0.6, 1, 0, -4, 0, 0, 1, 0, tm(4), nI = c(30, 60, 90, 120), maxn = 100)
# overrun and a coarser grid
design_cases(3, 4, 0.025, 0.1, 0, 1, 9, 1, 0, 0, -2, 0, tm(3), overrun = 5)
design_cases(3, 4, 0.025, 0.1, 0, 1, 9, 1, 0, 0, -2, 0, tm(3), r = 12)

# ---- gsProbability: fn "gsprob", args (out, k, nth, r, overrun, theta[nth], nI[k], a[k], b[k]); out = field * 100 + index (1 lower prob, 2 upper prob, 3 en), probabilities column-major
add_gsprob <- function(theta, nI, a, b, r = 18, overrun = 0) {
  k <- length(nI); x <- gsProbability(k = k, theta = theta, n.I = nI, a = a, b = b, r = r, overrun = overrun)
  pre <- c(k, length(theta), r, overrun, theta, nI, a, b)
  add1 <- function(f, i, v) cases[[length(cases) + 1]] <<- case("gsprob", c(f * 100 + i - 1, pre), v, rel = 1e-9, abs = 1e-12)
  for (j in seq_along(x$lower$prob)) add1(1, j, x$lower$prob[j])
  for (j in seq_along(x$upper$prob)) add1(2, j, x$upper$prob[j])
  for (j in seq_along(x$en)) add1(3, j, x$en[j])
}
add_gsprob(c(0, 0.3), c(10, 20, 30), c(-2, -1.5, -1.2), c(3, 2.5, 2))
add_gsprob(c(0, 0.2, 0.4), c(25, 50, 75, 100), c(-1, -1, -0.5, 0.5), c(2.8, 2.5, 2.2, 2), r = 16)
add_gsprob(c(-0.1, 0.5), c(5, 12), c(-20, -20), c(2, 1.9), overrun = 2)
add_gsprob(c(0.25), c(8, 16, 24, 32, 40), rep(-20, 5), c(4, 3.3, 2.9, 2.6, 2.4), r = 24)
add_gsprob(c(0, 1), c(1.5, 3, 6), c(-0.5, 0, 0.5), c(2.2, 2.2, 2.2), r = 10, overrun = 1)
x <- gsDesign(k = 4, test.type = 4, alpha = 0.025, beta = 0.1, sfu = sfLDOF, sfl = sfHSD, sflpar = -2)
add_gsprob(c(0, x$delta, 1.3 * x$delta), x$n.I, x$lower$bound, x$upper$bound)
add_gsprob(c(0.5 * x$delta, x$delta), 0.8 * x$n.I, x$lower$bound, x$upper$bound, r = 18, overrun = 3)

# ---- gsCP: fn "gscp", args (out, k, onesided, r, i, zi, nth, theta[nth], nI[k], lo[k], hi[k]); out = field * 100 + index (1 lower, 2 upper, 3 en) of the conditional design
add_cp <- function(x, i, zi, theta, r = 18) {
  y <- gsCP(x, theta = theta, i = i, zi = zi, r = r)
  one <- x$test.type == 1
  lo <- if (one) rep(0, x$k) else x$lower$bound
  pre <- c(x$k, one, r, i, zi, length(theta), theta, x$n.I, lo, x$upper$bound)
  add1 <- function(f, j, v) cases[[length(cases) + 1]] <<- case("gscp", c(f * 100 + j - 1, pre), v, rel = 1e-9, abs = 1e-12)
  if (!one) for (j in seq_along(y$lower$prob)) add1(1, j, y$lower$prob[j])
  for (j in seq_along(y$upper$prob)) add1(2, j, y$upper$prob[j])
  for (j in seq_along(y$en)) add1(3, j, y$en[j])
}
xs <- list(gsDesign(k = 4, test.type = 4, alpha = 0.025, beta = 0.1, sfu = sfLDOF, sfl = sfHSD, sflpar = -2),
           gsDesign(k = 3, test.type = 1, alpha = 0.025, beta = 0.1, sfu = sfHSD, sfupar = -4),
           gsDesign(k = 5, test.type = 2, alpha = 0.05, beta = 0.2, sfu = sfPower, sfupar = 2))
for (x in xs) for (i in c(1, 2)) for (zi in c(-0.5, 0.8, 1.7)) {
  add_cp(x, i, zi, c(zi / sqrt(x$n.I[i]), 0, x$delta))
}
add_cp(xs[[1]], 3, 1.1, c(0.2, 0.4), r = 12)

# ---- nNormal: fn "nnormal", args (out, delta1, sd, sd2, alpha, beta, ratio, sided, delta0, n); sd2 < 0 means NULL, n <= 0 means NULL; out 0 n or power, 1 n1, 2 n2, 3 se
add_nn <- function(delta1, sd, sd2, alpha, beta, ratio, sided, delta0, n) {
  y <- nNormal(delta1 = delta1, sd = sd, sd2 = if (sd2 < 0) NULL else sd2, alpha = alpha, beta = beta, ratio = ratio, sided = sided,
               delta0 = delta0, n = if (n <= 0) NULL else n, outtype = 3)
  pre <- c(delta1, sd, sd2, alpha, beta, ratio, sided, delta0, n)
  vals <- c(if (n <= 0) y$n else y$Power, y$n1, y$n2, y$se)
  for (j in seq_along(vals)) cases[[length(cases) + 1]] <<- case("nnormal", c(j - 1, pre), vals[j], rel = 1e-12, abs = 1e-14)
}
add_nn(1, 1.7, -1, 0.025, 0.1, 1, 1, 0, 0)
add_nn(0.5, 1.1, 2, 0.025, 0.2, 1, 1, 0, 0)
add_nn(0.5, 1.1, -1, 0.025, 0.2, 2, 1, 0, 0)
add_nn(0.5, 1.2, -1, 0.025, 0.1, 1, 1, -0.1, 0)
add_nn(-0.3, 0.9, 1.4, 0.05, 0.15, 0.5, 2, 0, 0)
add_nn(0.5, 1.1, 2, 0.025, 0.2, 1.5, 1, 0.1, 80)
add_nn(0.4, 1, -1, 0.05, 0.2, 1, 2, 0, 120)

# ---- nBinomial: fn "nbinom", args (out, p1, p2, alpha, beta, delta0, ratio, sided, scale 0 difference 1 RR 2 OR 3 lnor, n); n <= 0 means NULL;
#   out 0 n or power, 1 n1, 2 n2, 3 sigma0, 4 sigma1, 5 p10, 6 p20
add_nb <- function(p1, p2, alpha, beta, delta0, ratio, sided, scale, n) {
  sc <- c("Difference", "RR", "OR", "LNOR")[scale + 1]
  y <- nBinomial(p1 = p1, p2 = p2, alpha = alpha, beta = beta, delta0 = delta0, ratio = ratio, sided = sided, scale = sc,
                 n = if (n <= 0) NULL else n, outtype = 3)
  pre <- c(p1, p2, alpha, beta, delta0, ratio, sided, scale, n)
  vals <- c(if (n <= 0) y$n else y$Power, y$n1, y$n2, y$sigma0, y$sigma1, y$p10, y$p20)
  for (j in seq_along(vals)) cases[[length(cases) + 1]] <<- case("nbinom", c(j - 1, pre), vals[j], rel = 1e-10, abs = 1e-13)
}
for (sc in 0:3) {
  add_nb(0.3, 0.15, 0.025, 0.1, 0, 1, 1, sc, 0)
  add_nb(0.3, 0.15, 0.05, 0.2, 0, 2, 2, sc, 0)
  add_nb(0.25, 0.1, 0.025, 0.1, 0, 0.5, 1, sc, 150)
}
add_nb(0.2, 0.15, 0.025, 0.1, -0.1, 1, 1, 0, 0)
add_nb(0.35, 0.3, 0.025, 0.2, 0.02, 1.5, 1, 0, 0)
add_nb(0.2, 0.2, 0.025, 0.1, 0.1, 1, 1, 0, 0)
add_nb(0.3, 0.2, 0.025, 0.1, 0.2, 1, 1, 1, 0)
add_nb(0.3, 0.2, 0.025, 0.1, 0.1, 1, 1, 2, 0)
add_nb(0.4, 0.3, 0.025, 0.1, 0.05, 2, 1, 0, 200)
add_nb(0.7, 0.55, 0.025, 0.1, 0, 1, 1, 0, 0)

# ---- nSurv (T and minfup given; one stratum): fn "nsurv", args (out, hr, hr0, ratio, alpha, beta, sided, T, minfup, method, nR, nS, R[nR], gamma[nR], S[nS], lambda[nS+1], etaC[nS+1], etaE[nS+1]);
#   beta < 0 means NULL (power); method 0 LachinFoulkes 1 Schoenfeld 2 Freedman 3 BernsteinLagakos; out 0 N, 1 d, 2 power, 3 gamma[1], 4 eDC, 5 eDE, 6 eDC0, 7 eDE0, 8 eNC, 9 eNE, 10 R[1]
add_ns <- function(lambda, hr, hr0, eta, etaE, gamma, R, S, T, minfup, ratio, alpha, beta, sided, method) {
  nlam <- length(S) + 1
  y <- nSurv(lambdaC = lambda, hr = hr, hr0 = hr0, eta = eta, etaE = etaE, gamma = gamma, R = R, S = if (length(S)) S else NULL, T = T,
             minfup = minfup, ratio = ratio, alpha = alpha, beta = if (beta < 0) NULL else beta, sided = sided,
             method = c("LachinFoulkes", "Schoenfeld", "Freedman", "BernsteinLagakos")[method + 1])
  pre <- c(hr, hr0, ratio, alpha, beta, sided, T, minfup, method, length(R), length(S), R, gamma, S, rep_len(lambda, nlam), rep_len(eta, nlam), rep_len(etaE, nlam))
  vals <- c(y$n, y$d, y$power, y$gamma[1], sum(y$eDC), sum(y$eDE), sum(y$eDC0), sum(y$eDE0), sum(y$eNC), sum(y$eNE), y$R[1])
  for (j in seq_along(vals)) cases[[length(cases) + 1]] <<- case("nsurv", c(j - 1, pre), vals[j], rel = 1e-9, abs = 1e-12)
}
for (m in 0:3) {
  add_ns(log(2) / 6, 0.6, 1, 0, 0, 1, 12, NULL, 18, 6, 1, 0.025, 0.1, 1, m)
  add_ns(c(0.1, 0.05), 0.65, 1, 0.01, 0.02, c(2.5, 5, 7.5, 10), c(2, 2, 2, 6), 8, 30, 18, 2, 0.025, 0.15, 1, m)
  add_ns(log(2) / 12, 0.7, 1, 0.005, 0.005, 1, 18, NULL, 30, 12, 0.5, 0.05, 0.2, 2, m)
  add_ns(c(0.08, 0.06, 0.04), 0.75, 1, 0, 0, c(3, 6), c(4, 8), c(6, 12), 36, 24, 1.5, 0.025, 0.1, 1, m)
  add_ns(log(2) / 6, 0.6, 1, 0, 0, 5, 12, NULL, 18, 6, 1, 0.025, -1, 1, m)
  add_ns(c(0.1, 0.05), 0.65, 1, 0.01, 0.01, c(2.5, 5), c(2, 4), 8, 24, 12, 1, 0.025, -1, 1, m)
}
add_ns(log(2) / 6, 0.6, 0.8, 0, 0, 1, 12, NULL, 18, 6, 1, 0.025, 0.1, 1, 0)
add_ns(log(2) / 6, 0.5, 1.2, 0.01, 0.01, 1, 12, NULL, 18, 6, 2, 0.025, 0.1, 1, 3)
add_ns(log(2) / 6, 0.6, 0.8, 0, 0, 1, 12, NULL, 18, 6, 1, 0.025, -1, 1, 3)
add_ns(log(2) / 6, 0.6, 1, 0, 0, c(2, 4), c(6, 6), NULL, 24, 12, 1, 0.025, 0.1, 1, 0)
add_ns(log(2) / 6, 0.6, 1, 0, 0, c(2, 4, 6), c(3, 3, 3), NULL, 24, 12, 1, 0.025, 0.1, 1, 0)

emit("gsdesign", "gsDesign", list(cases))
