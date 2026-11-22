# locfit, one predictor: local regression and likelihood, the kernels, the evaluation structures, the adaptive bandwidth
# criteria and the fit summaries. Two goldens: locfit (a fixed bandwidth by nn and h) and locfit_adapt (acri cp, ici, ok).
# Tolerance: 1e-9 relative for the rational kernels with the gaussian family (no libm call in the fit); 1e-8 for the
# gaussian kernel and the binomial and poisson families, where exp and log differ from R's libm in the last place and the
# ill-conditioned local normal equations (condition near 1e7) amplify that to a few parts in 1e9.
#   args: (n, kern, deg, fam, nn, h, ev, cut, mg, quasi, m, acri, adpen, link, x[n] sorted, y[n]) with kern R's integer (1 rect, 2 epan,
#   3 bisq, 4 tcub, 5 trwt, 6 gauss, 7 tria, 8 quqt, 9 6cub, 11 expl), fam 0 gaussian / 1 binomial / 2 poisson,
#   ev 0 tree / 2 dat / 3 grid / 4 kdtree, m new points seq(min x, max x, length = m), acri 0 none / 1 cp / 2 ici / 4 ok.
#   fn: vertex columns summed by rank in x (vx vh vc0 vc1 vn0 vn1 vt0 vt1 vl0 vl1 vl2), nv, fit (fitted), pred (predict),
#   seg sel sep (predict se.fit, band global, local, prediction), plotfit plotse (predict on the 100 point plot grid, tree only),
#   lk df0 df1 rv (dp of the fit), gcv cp aic.
suppressMessages(library(locfit))
kerns <- c(1, 2, 3, 4, 5, 6, 7, 8, 9, 11)
knames <- c("rect", "epan", "bisq", "tcub", "triw", "gauss", "tria", "quqt", "6cub", "expl")
fnames <- c("gaussian", "binomial", "poisson", "gamma", "geometric")
lnames <- c("default", "default", "default", "identity", "log", "logit", "inverse", "sqrt", "arcsin")  # by R link integer + 1 (0 = default)
acris <- c("none", "cp", "ici", "mindex", "ok")
wsum <- function(v) sum(v * seq_along(v))
gen <- function(cfgs, adaptive, extra = FALSE) {
  cases <- list()
  for (cfg in cfgs) {
    ev <- c(0, 0, 0, 2, 3, 4)[(cfg - 1) %% 6 + 1]
    kern <- kerns[(cfg - 1) %% 10 + 1]
    fam <- c(0, 0, 0, 1, 2)[(cfg * 7 - 1) %% 5 + 1]
    deg <- c(2, 1, 2, 3, 0, 1, 2)[(cfg * 3) %% 7 + 1]
    n <- sample(30:50, 1)
    x <- sort(unique(round(runif(n), 5))); n <- length(x)
    mode <- cfg %% 3
    nn <- if (mode == 1) 0 else runif(1, 0.35, 0.8)
    h <- if (mode == 1) runif(1, 0.18, 0.4) else if (mode == 2) runif(1, 0.05, 0.3) else 0
    if (fam == 1) { nn <- max(nn, 0.5); if (mode == 1) h <- max(h, 0.3); deg <- min(deg, 2) }
    link <- 0
    if (extra) {
      fam <- c(3, 4, 2, 0, 3, 4, 2, 3, 0)[cfg %% 9 + 1]
      link <- switch(as.character(fam), "3" = c(4, 6, 3)[cfg %% 3 + 1], "4" = c(4, 3)[cfg %% 2 + 1], "2" = c(3, 7)[cfg %% 2 + 1], "0" = 4)
      if (fam == 3 && link == 6) deg <- min(deg, 1)
    }
    acri <- 0; adpen <- 0
    if (adaptive) {
      acri <- c(1, 2, 4)[cfg %% 3 + 1]
      adpen <- if (acri == 1) runif(1, 1.5, 3) else if (acri == 2) runif(1, 1, 2.5) else 0
      nn <- if (acri == 4) runif(1, 0.3, 0.6) else runif(1, 0.1, 0.3)
      h <- 0
      if (fam == 1) { nn <- max(nn, 0.35); deg <- min(deg, 1) }
    }
    mu <- sin(4 * x)
    y <- if (fam == 0 && link == 4) round(exp(0.8 * mu + 0.3) + rnorm(n, 0, 0.2), 6) else if (fam == 0) round(mu + rnorm(n, 0, 0.3), 6) else if (fam == 1) rbinom(n, 1, 1 / (1 + exp(-2 * mu)))
         else if (fam == 3) round(rgamma(n, shape = 5, rate = 5 / exp(0.8 * mu + 0.5)), 6) else if (fam == 4) rgeom(n, 1 / (1 + exp(0.8 * mu + 0.5))) else rpois(n, exp(0.8 * mu + 0.5))
    cut <- if (ev == 4) 0.8 else sample(c(0.5, 0.8, 1.2), 1)
    mg <- sample(6:25, 1)
    quasi <- (cfg %% 2 == 0) * 1
    m <- 9
    fam_name <- paste0(if (quasi) "q" else "", fnames[fam + 1])
    evo <- switch(as.character(ev), "0" = rbox(cut = cut), "2" = dat(), "3" = lfgrid(mg = mg), "4" = rbox(cut = cut, type = "kdtree"))
    f <- tryCatch(suppressWarnings(locfit(y ~ lp(x, nn = nn, h = h, adpen = adpen, deg = deg, acri = acris[match(acri, c(0, 1, 2, 3, 4))]),
                                          family = fam_name, link = lnames[link + 1], kern = knames[match(kern, kerns)], ev = evo)), error = function(e) NULL)
    if (is.null(f)) { message("skip(error) ", cfg, " ev ", ev, " fam ", fam, " kern ", kern); next }
    cf <- f$eva$coef
    if (any(!is.finite(cf)) || any(cf == 0.1278433) || any(!is.finite(f$dp[c("lk", "df1", "df2", "rv")]))) { message("skip(nonfinite) ", cfg, " ev ", ev, " fam ", fam, " kern ", kern); next }
    nv <- f$nvc["nv"]
    xv <- f$eva$xev
    o <- if (ev == 2) seq_along(xv) else order(xv)
    a <- c(n, kern, deg, fam, nn, h, ev, cut, mg, quasi, m, acri, adpen, link, x, y)
    trel <- if (kern == 6 || fam != 0 || link != 0) 1e-8 else 1e-9
    add <- function(fn, want, rel = trel, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = rel, abs = abs)
    add("nv", nv, 0, 0)
    add("vx", wsum(xv[o])); add("vh", wsum(cf[o, 10]))
    add("vc0", wsum(cf[o, 1])); add("vc1", wsum(cf[o, 2]))
    nab <- if (fam != 0) 1e-6 else if (trel > 1e-9) 1e-8 else 1e-11  # the parametric part is subtracted from an O(1) norm, and the global fit it comes from stops Newton at a likelihood change under 1e-6 s0: the absolute error stays at that scale
    nrel <- if (fam != 0) 1e-6 else trel  # newton stops at a likelihood change under 1e-6 s0: a libm last-place difference can add or drop the final step
    add("vn0", wsum(cf[o, 3]), nrel, nab); add("vn1", wsum(cf[o, 4]), nrel, nab)
    add("vt0", wsum(cf[o, 5]), nrel, nab); add("vt1", wsum(cf[o, 6]), nrel, nab)
    add("vl0", wsum(cf[o, 7])); add("vl1", wsum(cf[o, 8])); add("vl2", wsum(cf[o, 9]))
    add("fit", wsum(as.numeric(fitted(f))))
    dp <- f$dp
    add("lk", dp["lk"]); add("df0", dp["df1"]); add("df1", dp["df2"]); add("rv", dp["rv"])
    add("gcv", -2 * n * dp["lk"] / (n - dp["df1"])^2)
    add("cp", -2 * dp["lk"] - n + 2 * dp["df1"])
    add("aic", -2 * dp["lk"] + 2 * dp["df1"])
    if (ev != 2) {
      nx <- seq(min(x), max(x), length = m)
      add("pred", wsum(as.numeric(predict(f, nx))))
      for (b in c("global", "local", "prediction")) {
        pr <- predict(f, nx, band = b)
        add(c(global = "seg", local = "sel", prediction = "sep")[[b]], wsum(as.numeric(pr$se.fit)))
      }
    }
    if (ev == 0) {
      nx <- seq(min(x), max(x), length = 100)
      pr <- predict(f, nx, band = "global")
      add("plotfit", wsum(as.numeric(pr$fit))); add("plotse", wsum(as.numeric(pr$se.fit)))
    }
  }
  cases
}
set.seed(20261230)
emit("locfit", "locfit", list(gen(1:42, FALSE)))
set.seed(20270101)
emit("locfit_adapt", "locfit", list(gen(1:30, TRUE)))
set.seed(20270102)
emit("locfit_family", "locfit", list(gen(1:30, FALSE, TRUE)))
