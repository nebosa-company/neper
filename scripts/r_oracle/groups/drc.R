# drc: drm() fits of the dose-response families, with ED, logLik, lack of fit and the Poisson and robust variants.
#   args: (kind, alpha, mode, K, fixed b c d e f (NA = free), n, dose[n], resp[n], curve[n] (0-based), sel1, sel2)
#   fn: par (sel1 = index in the parameter-major vector), se (sel1), value, rv, loglik, aic, ed / edse (sel1 = curve, sel2 = level),
#       edlo / edhi (95% delta interval), lofF, lofp, fit (sel1 = observation)
#   Agreement is to the tolerance of drm's own BFGS stop (reltol 1e-7) only where a case says so; Neper runs the same iteration.
suppressMessages(library(drc))
cases <- list()
set.seed(20261230)
TOL <- 1e-9
TOLH <- 1e-5  # a second difference of finite-difference gradients (optimHess): rounding noise of ~1e-8 relative
rec <- function(kind, alpha, mode, fx, dose, resp, grp, m, ed_levels = NULL, ed_fun = NULL, tol = TOL) {
  # UCRS with two curves: BFGS from drc start values (identical to drc ssfct) stops ~2e-6 (relative) from drc on a flat valley, within its reltol 1e-7 path noise; stated per case
  if (kind == 6 && length(unique(grp)) == 2) tol <- 1e-4
  th <- max(TOLH, tol)
  if (tol == 1e-4) th <- 1e-3  # curvature-derived values (se, covariance, t, p, ED interval) move more than the parameters do
  n <- length(dose); K <- length(unique(grp))
  hdr <- c(kind, alpha, mode, K, fx, n, dose, resp, grp - 1)
  add <- function(fn, s1, s2, want, rel = tol) cases[[length(cases) + 1]] <<- case(fn, c(hdr, s1, s2), want, rel = rel, abs = 1e-12)
  cf <- as.numeric(coef(m)); np <- length(cf); V <- vcov(m)
  # robust "median" minimises a sum of absolute residuals, which has kinks: BFGS from the same start ends within about 1% of
  # R's point but not on it (one ulp of exp or log changes which kink it settles on), and the numerical Hessian is meaningless
  if (mode == 1) {
    for (i in seq_len(np)) add("par", i - 1, 0, cf[i], 3e-2)
    add("fit", 0, 0, fitted(m)[1], 5e-2); add("fit", n - 1, 0, fitted(m)[n], 5e-2)
    return(invisible())
  }
  for (i in seq_len(np)) add("par", i - 1, 0, cf[i])
  for (i in seq_len(np)) add("se", i - 1, 0, sqrt(V[i, i]), th)
  if (np >= 2) add("covar", 0, K, V[1, 1 + K], th)
  if (mode != 2) add("rv", 0, 0, summary(m)$resVar)
  add("value", 0, 0, if (mode == 2) -as.numeric(logLik(m)) + sum(log(gamma(resp + 1))) else if (mode == 0) sum(residuals(m)^2) else m$fit$value)
  add("loglik", 0, 0, as.numeric(logLik(m)))
  if (mode != 2) add("aic", 0, 0, AIC(m))
  # BC and CRS find their ED by uniroot (default tolerance); a model whose bracket fails has no ED and is redrawn
  if (!is.null(ed_levels)) {
    e <- ED(m, ed_levels, interval = "delta", display = FALSE)
    if (any(!is.finite(e))) stop("ED not finite")
    if (K == 2) for (p in ed_levels) EDcomp(m, c(p, p), display = FALSE)
    for (j in seq_along(ed_levels)) {
      idx <- seq(j, nrow(e), by = length(ed_levels))
      for (k in seq_along(idx)) {
        add("ed", k - 1, ed_levels[j], e[idx[k], 1]); add("edse", k - 1, ed_levels[j], e[idx[k], 2], th)
        add("edlo", k - 1, ed_levels[j], e[idx[k], 3], th); add("edhi", k - 1, ed_levels[j], e[idx[k], 4], th)
      }
    }
  }
  if (K == 2) {
    pn <- sub(":.*", "", names(coef(m)))[seq(1, np, by = K)]
    for (j in seq_along(pn)) for (ratio in c(1, 0)) {
      cp <- compParm(m, pn[j], if (ratio == 1) "/" else "-", display = FALSE)
      add("cpest", j - 1, ratio, cp[1, 1]); add("cpse", j - 1, ratio, cp[1, 2], th)
      add("cpt", j - 1, ratio, cp[1, 3], th); add("cpp", j - 1, ratio, cp[1, 4], th)
    }
    if (!is.null(ed_levels)) for (p in ed_levels) {
      sc <- EDcomp(m, c(p, p), display = FALSE)
      add("selest", p, p, sc[1, 1]); add("selse", p, p, sc[1, 2], th)
      add("selt", p, p, sc[1, 3], th); add("selp", p, p, sc[1, 4], th)
    }
  }
  if (mode == 0 && K == 1) {
    mf <- modelFit(m)
    add("lofF", 0, 0, mf[2, 4]); add("lofp", 0, 0, mf[2, 5])
  }
  add("fit", 0, 0, fitted(m)[1])
  add("fit", n - 1, 0, fitted(m)[n])
}

# model table: R constructor, kind, alpha, fixed values
models <- list(
  list("LL.2", function() LL.2(), 0, 0, c(NA, 0, 1, NA, 1)),
  list("LL.3", function() LL.3(), 0, 0, c(NA, 0, NA, NA, 1)),
  list("LL.3u", function() LL.3u(), 0, 0, c(NA, NA, 1, NA, 1)),
  list("LL.4", function() LL.4(), 0, 0, c(NA, NA, NA, NA, 1)),
  list("LL.5", function() LL.5(), 0, 0, c(NA, NA, NA, NA, NA)),
  list("W1.2", function() W1.2(), 1, 0, c(NA, 0, 1, NA, NA)),
  list("W1.3", function() W1.3(), 1, 0, c(NA, 0, NA, NA, NA)),
  list("W1.4", function() W1.4(), 1, 0, c(NA, NA, NA, NA, NA)),
  list("W2.2", function() W2.2(), 2, 0, c(NA, 0, 1, NA, NA)),
  list("W2.3", function() W2.3(), 2, 0, c(NA, 0, NA, NA, NA)),
  list("W2.4", function() W2.4(), 2, 0, c(NA, NA, NA, NA, NA)),
  list("G.2", function() G.2(), 3, 0, c(NA, 0, 1, NA, NA)),
  list("G.3", function() G.3(), 3, 0, c(NA, 0, NA, NA, NA)),
  list("G.4", function() G.4(), 3, 0, c(NA, NA, NA, NA, NA)),
  list("BC.4", function() BC.4(), 4, 0, c(NA, 0, NA, NA, NA)),
  list("BC.5", function() BC.5(), 4, 0, c(NA, NA, NA, NA, NA)),
  list("CRS.4a", function() CRS.4a(), 5, 1, c(NA, 0, NA, NA, NA)),
  list("CRS.4c", function() CRS.4c(), 5, 0.25, c(NA, 0, NA, NA, NA)),
  list("CRS.5a", function() CRS.5a(), 5, 1, c(NA, NA, NA, NA, NA)),
  # drc's UCRS.4a and UCRS.4c fail inside drm itself (their ssfct returns the wrong length), so only UCRS.5a is a model R can fit
  list("UCRS.5a", function() UCRS.5a(), 6, 1, c(NA, NA, NA, NA, NA))
)
doses_log <- c(0.1, 0.3, 1, 3, 10, 30, 100)
doses_lin <- seq(0, 8, by = 1)
mean_of <- function(spec, dose, p5) {
  fx <- spec[[5]]; kind <- spec[[3]]; alpha <- spec[[4]]
  p <- ifelse(is.na(fx), p5, fx); b <- p[1]; c <- p[2]; d <- p[3]; e <- p[4]; f <- p[5]
  switch(kind + 1,
    c + (d - c) / (1 + exp(b * log(dose / e)))^f,
    c + (d - c) * exp(-exp(b * (log(dose) - log(e)))),
    c + (d - c) * (1 - exp(-exp(b * (log(dose) - log(e))))),
    c + (d - c) * exp(-exp(b * (dose - e))),
    c + (d + f * dose - c) / (1 + exp(b * (log(dose) - log(e)))),
    c + (d - c + f * exp(-1 / dose^alpha)) / (1 + exp(b * (log(dose) - log(e)))),
    d - (d - c + f * exp(-1 / dose^alpha)) / (1 + exp(b * (log(dose) - log(e)))))
}
draw <- function(spec) {
  kind <- spec[[3]]
  b <- runif(1, 0.8, 3); cc <- runif(1, 0, 3); d <- cc + runif(1, 4, 12); e <- exp(runif(1, log(1), log(20))); f <- runif(1, 0.6, 1.8)
  if (kind == 3) { b <- -runif(1, 0.4, 1.2); e <- runif(1, 3, 5) }
  if (kind == 1 || kind == 2) b <- runif(1, 0.5, 2)
  if (kind == 4) f <- runif(1, 0.2, 1) * (d - cc) / 20
  if (kind == 5 || kind == 6) f <- runif(1, 0.3, 1) * (d - cc)
  fx <- spec[[5]]
  if (!is.na(fx[2])) cc <- fx[2]
  if (!is.na(fx[3])) { d <- fx[3]; if (is.na(fx[2])) cc <- runif(1, 0, 0.3) }
  c(b, cc, d, e, f)
}
for (spec in models) {
  made <- 0; tries <- 0
  while (made < 2 && tries < 12) {
    tries <- tries + 1
    kind <- spec[[3]]
    dose <- rep(if (kind == 3) doses_lin else if (spec[[1]] %in% c("W1.2", "W1.3", "W1.4", "LL.2", "LL.4") && made == 1) c(0, doses_log) else doses_log, each = sample(2:3, 1))
    p5 <- draw(spec); sdv <- 0.04 * abs(p5[3] - ifelse(is.na(spec[[5]][2]), p5[2], spec[[5]][2]))
    if (!is.na(spec[[5]][3]) && spec[[5]][3] == 1) sdv <- 0.03
    y <- round(mean_of(spec, dose, p5) + rnorm(length(dose), 0, sdv), 4)
    m <- try(suppressWarnings(drm(y ~ dose, fct = spec[[2]]())), silent = TRUE)
    if (inherits(m, "try-error")) next
    # a flat optimum (BFGS needing hundreds of gradients) is decided by the last bit of exp and log, which R's C library and Neper's differ in
    if (m$fit$counts[2] > (if (kind >= 4) 40 else 100)) { cat("flat optimum, redrawn:", spec[[1]], m$fit$counts[2], "\n"); next }
    # an unidentified parameter (standard error beyond twice its size) makes the curvature pure rounding noise in both programs
    if (any(sqrt(diag(vcov(m))) > 2 * abs(coef(m)))) { cat("unidentified, redrawn:", spec[[1]], "\n"); next }
    levs <- c(10, 50, 90)
    ok <- try(rec(kind, spec[[4]], 0, spec[[5]], dose, y, rep(1, length(dose)), m, levs), silent = TRUE)
    if (inherits(ok, "try-error")) cat("skip", spec[[1]], conditionMessage(attr(ok, "condition")), "\n")
    else made <- made + 1
  }
  cat(spec[[1]], made, "\n")
}
spec_of <- function(name) models[[which(vapply(models, function(s) s[[1]], "") == name)]]
usable <- function(m) {
  if (inherits(m, "try-error")) return(FALSE)
  se <- suppressWarnings(sqrt(diag(vcov(m))))
  isTRUE(m$fit$counts[2] <= if (grepl("UCRS", paste(m$fct$name))) 25 else if (grepl("BC|CRS", paste(m$fct$name))) 40 else 100) && !anyNA(se) && !any(se > 2 * abs(coef(m)))
}
# Poisson counts and the robust median fit
for (nm in c("LL.3", "W1.3", "LL.3", "W1.3")) {
  spec <- spec_of(nm); n_ok <- FALSE; tries <- 0
  while (!n_ok && tries < 12) {
    tries <- tries + 1
    dose <- rep(doses_log, each = 3); p5 <- c(runif(1, 0.8, 2.5), 0, runif(1, 30, 80), exp(runif(1, 0, 3)), 1)
    y <- rpois(length(dose), pmax(mean_of(spec, dose, p5), 0.01))
    m <- try(suppressWarnings(drm(y ~ dose, fct = spec[[2]](), type = "Poisson")), silent = TRUE)
    if (!usable(m)) next
    r <- try(rec(spec[[3]], 0, 2, spec[[5]], dose, y, rep(1, length(dose)), m, c(10, 50, 90)), silent = TRUE)
    n_ok <- !inherits(r, "try-error")
  }
  cat("poisson", nm, n_ok, "\n")
}
# robust criteria. Their objectives are kinked, so BFGS paths differ between math libraries and the fit itself is compared only for
# "median" at a stated loose tolerance; every criterion is compared at R's own optimum (Neper evaluates the criterion, the post-fit
# scale and the Hessian standard errors at R's coefficients), where the arithmetic is deterministic. scale is drc's scale for the
# trimmed, tukey and winsor metrics: the MAD of a least-trimmed-squares fit.
modes_rob <- c(median = 1, trimmed = 3, tukey = 4, winsor = 5, lms = 6, lts = 7)
for (rt in rep(names(modes_rob), each = 2)) {
  spec <- spec_of("LL.4"); n_ok <- FALSE; tries <- 0
  while (!n_ok && tries < 12) {
    tries <- tries + 1
    dose <- rep(doses_log, each = 3); p5 <- draw(spec)
    y <- round(mean_of(spec, dose, p5) + rnorm(length(dose), 0, 0.04 * (p5[3] - p5[2])), 4)
    y[sample(length(y), 1)] <- y[1] + (p5[3] - p5[2]) * runif(1, 0.5, 1)
    dfr <- data.frame(dose = dose, y = y); assign("dfr", dfr, envir = globalenv())
    m <- try(suppressWarnings(drm(y ~ dose, data = dfr, fct = LL.4(), robust = rt)), silent = TRUE)
    if (inherits(m, "try-error")) { cat(rt, substr(as.character(m), 1, 150), "\n"); next }
    sc <- 1
    if (rt %in% c("trimmed", "tukey", "winsor")) sc <- mad(residuals(suppressWarnings(drm(y ~ dose, data = dfr, fct = LL.4(), robust = "lts"))), 0)
    mode <- modes_rob[[rt]]; n <- length(dose); cf <- as.numeric(coef(m))
    hdr <- c(0, 0, mode, 1, spec[[5]], n, dose, y, rep(0, n))
    addr <- function(fn, s2, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, c(hdr, sc, s2, cf), want, rel = rel, abs = 1e-12)
    addr("rcrit", 0, m$fit$ovalue)
    addr("rvalue", 0, m$fit$value)
    addr("rrv", 0, m$fit$value / df.residual(m))
    V <- try(vcov(m), silent = TRUE)
    if (!inherits(V, "try-error") && all(is.finite(V))) for (i in seq_along(cf)) addr("rse", i - 1, sqrt(V[i, i]), 1e-5)
    if (rt == "median" && usable(m)) try(rec(0, 0, 1, spec[[5]], dose, y, rep(1, n), m, c(10, 50, 90)), silent = TRUE)
    n_ok <- TRUE
  }
  cat("robust", rt, n_ok, "\n")
}
# two curves, own parameters each
for (nm in c("LL.4", "LL.4", "W1.4", "LL.3", "W2.4", "BC.4", "BC.4", "BC.5", "CRS.4a", "CRS.4a", "CRS.5a", "UCRS.5a", "UCRS.5a")) {
  spec <- spec_of(nm); n_ok <- FALSE; tries <- 0
  while (!n_ok && tries < 40) {
    tries <- tries + 1
    dose <- rep(doses_log, each = 2); n1 <- length(dose)
    pa <- draw(spec); pb <- draw(spec)
    ya <- round(mean_of(spec, dose, pa) + rnorm(n1, 0, 0.04 * abs(pa[3] - pa[2])), 4)
    yb <- round(mean_of(spec, dose, pb) + rnorm(n1, 0, 0.04 * abs(pb[3] - pb[2])), 4)
    d2 <- c(dose, dose); y2 <- c(ya, yb); g <- rep(1:2, each = n1)
    m <- try(suppressWarnings(drm(y2 ~ d2, curveid = g, fct = spec[[2]]())), silent = TRUE)
    if (!usable(m)) next
    r <- try(rec(spec[[3]], spec[[4]], 0, spec[[5]], d2, y2, g, m, c(10, 50, 90)), silent = TRUE)
    if (inherits(r, "try-error")) cat(conditionMessage(attr(r, "condition")), "\n")
    n_ok <- !inherits(r, "try-error")
  }
  cat("two curves", nm, n_ok, "\n")
}
# mselect: the log-likelihood, AIC, lack-of-fit p value and residual variance of each model, and the AIC order
msel_names <- c("LL.4", "LL.3", "W1.4", "W2.4", "W1.3")
for (rep in 1:3) {
  n_ok <- FALSE; tries <- 0
  while (!n_ok && tries < 15) {
    tries <- tries + 1
    spec <- spec_of(c("LL.4", "W1.4", "LL.4")[rep]); dose <- rep(doses_log, each = 3); p5 <- draw(spec)
    y <- round(mean_of(spec, dose, p5) + rnorm(length(dose), 0, 0.05 * (p5[3] - p5[2])), 4)
    df0 <- data.frame(dose = dose, y = y)
    m0 <- try(suppressWarnings(drm(y ~ dose, data = df0, fct = LL.4())), silent = TRUE)
    if (!usable(m0)) next
    ms <- try(suppressWarnings(mselect(m0, list(LL.3(), W1.4(), W2.4(), W1.3()), sorted = "no")), silent = TRUE)
    if (inherits(ms, "try-error")) { cat("mselect error:", ms, "\n"); next }
    if (anyNA(ms)) { cat("NA in mselect\n"); print(ms); next }
    # every model has to be one of ours with a stable fit
    fits <- lapply(msel_names, function(nm) try(suppressWarnings(drm(y ~ dose, fct = spec_of(nm)[[2]]())), silent = TRUE))
    if (!all(vapply(fits, function(f) !inherits(f, "try-error") && f$fit$counts[2] <= 60, TRUE))) next
    hdr <- c(length(dose), dose, y, length(msel_names), unlist(lapply(msel_names, function(nm) { s <- spec_of(nm); c(s[[3]], s[[4]], s[[5]]) })))
    rk <- rank(ms[, "IC"])
    for (j in seq_along(msel_names)) {
      cases[[length(cases) + 1]] <- case("mselll", c(hdr, j - 1), ms[j, "logLik"], rel = 1e-9, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("mselic", c(hdr, j - 1), ms[j, "IC"], rel = 1e-9, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("mselof", c(hdr, j - 1), ms[j, "Lack of fit"], rel = 1e-7, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("mselrv", c(hdr, j - 1), ms[j, "Res var"], rel = 1e-9, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("mselrank", c(hdr, j - 1), rk[j], rel = 0, abs = 0)
    }
    n_ok <- TRUE
  }
  cat("mselect", n_ok, "\n")
}
emit("drc", "drc", list(cases))
