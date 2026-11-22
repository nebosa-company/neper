# locfit, one predictor, the families beyond locfit.R: the robust ones (r prefix, huber, cauchy, with and without the
# estimated scale of the quasi forms), weibull, circular, probab, nbinomial with prior weights, binomial with the
# identity and arcsin links and prior weights, and the adaptive criterion mindex. Same argument layout as locfit.R
# with (rob, w[n]) appended after y: rob 1 marks R's r prefix, w the prior weights.
# Tolerance: 1e-8 relative (the Newton iterations stop at a likelihood change under 1e-6 and the robust scale at 1e-6, so
# the last place of exp, log, pow and sin differing from the system libm shows at a few parts in 1e9); the variance and influence norms vn* vt* 1e-6.
#   Not compared for the quasi huber and cauchy families: lk df0 df1 rv gcv cp aic seg sep plotse, which R takes
#   at a global robust scale (rsc) this port does not compute.
suppressMessages(library(locfit))
kerns <- c(1, 2, 3, 4, 5, 6, 7, 8, 9, 11)
knames <- c("rect", "epan", "bisq", "tcub", "triw", "gauss", "tria", "quqt", "6cub", "expl")
lnames <- c("default", "default", "default", "identity", "log", "logit", "inverse", "sqrt", "arcsin")
acris <- c("none", "cp", "ici", "mindex", "ok")
wsum <- function(v) sum(v * seq_along(v))
# name, family code, quasi, rob, link
fams <- list(
  list("rgaussian", 0, 0, 1, 0), list("qrgaussian", 0, 1, 1, 0), list("huber", 7, 0, 0, 0), list("qhuber", 7, 1, 0, 0),
  list("cauchy", 8, 0, 0, 0), list("qcauchy", 8, 1, 0, 0), list("weibull", 5, 0, 0, 4), list("circular", 6, 0, 0, 0),
  list("probab", 9, 0, 0, 0), list("nbinomial", 4, 0, 0, 4), list("binomial", 1, 0, 0, 3), list("binomial", 1, 0, 0, 8),
  list("rpoisson", 2, 0, 1, 0), list("qrgamma", 3, 1, 1, 0), list("qrpoisson", 2, 1, 1, 0))
gen <- function(cfgs, mindex = FALSE) {
  cases <- list()
  for (cfg in cfgs) {
    fm <- fams[[(cfg - 1) %% length(fams) + 1]]
    famname <- fm[[1]]; fam <- fm[[2]]; quasi <- fm[[3]]; rob <- fm[[4]]; link <- fm[[5]]
    ev <- c(0, 0, 2, 3, 4, 0)[(cfg - 1) %% 6 + 1]
    kern <- kerns[(cfg * 3 - 1) %% 10 + 1]
    deg <- c(2, 1, 2, 1, 0, 1, 2)[(cfg * 3) %% 7 + 1]
    n <- sample(30:50, 1)
    x <- sort(unique(round(runif(n), 5))); n <- length(x)
    mode <- cfg %% 3
    nn <- if (mode == 1) 0 else runif(1, 0.4, 0.8)
    h <- if (mode == 1) runif(1, 0.2, 0.4) else if (mode == 2) runif(1, 0.1, 0.3) else 0
    if (fam == 1) { nn <- max(nn, 0.6); if (mode == 1) h <- max(h, 0.35); deg <- min(deg, 1) }
    if (fam %in% c(5, 6)) deg <- min(deg, 1)
    w <- rep(1, n)
    mu <- sin(4 * x)
    y <- switch(as.character(fam),
      "0" = , "7" = , "8" = { e <- if (fam == 8) rt(n, 2) * 0.2 else rnorm(n, 0, 0.3); o <- sample(n, 3); e[o] <- e[o] + 3; round(mu + e, 6) },
      "5" = { w <- rep(c(1.5, 2, 1)[cfg %% 3 + 1], n); round(rweibull(n, shape = w[1], scale = exp(0.5 * mu + 0.5)), 6) },
      "6" = round(1.5 * sin(3 * x) + rnorm(n, 0, 0.3), 6),
      "9" = rpois(n, exp(0.8 * mu + 0.5)),
      "4" = { w <- rep(c(2, 3, 1)[cfg %% 3 + 1], n); rnbinom(n, size = w[1], mu = w[1] * exp(0.4 * mu + 0.3)) },
      "1" = { w <- sample(5:20, n, replace = TRUE); rbinom(n, w, 0.5 + 0.25 * sin(3 * x)) },
      "2" = { o <- sample(n, 2); r <- rpois(n, exp(0.8 * mu + 0.5)); r[o] <- r[o] + 15; r },
      "3" = round(rgamma(n, shape = 5, rate = 5 / exp(0.8 * mu + 0.5)), 6))
    acri <- 0; adpen <- 0
    if (mindex) {
      acri <- 3; adpen <- runif(1, 1, 2.5)
      nn <- runif(1, 0.15, 0.3); h <- 0
      if (fam %in% c(1, 5, 6)) next
    }
    cut <- if (ev == 4) 0.8 else sample(c(0.5, 0.8), 1)
    mg <- sample(6:25, 1)
    m <- 9
    evo <- switch(as.character(ev), "0" = rbox(cut = cut), "2" = dat(), "3" = lfgrid(mg = mg), "4" = rbox(cut = cut, type = "kdtree"))
    f <- tryCatch(suppressWarnings(locfit(y ~ lp(x, nn = nn, h = h, adpen = adpen, deg = deg, acri = acris[match(acri, c(0, 1, 2, 3, 4))]),
                                          weights = w, family = famname, link = lnames[link + 1], kern = knames[match(kern, kerns)], ev = evo)), error = function(e) { message("err ", conditionMessage(e)); NULL })
    if (is.null(f)) { message("skip(error) ", cfg, " ", famname, " ev ", ev, " kern ", kern); next }
    cf <- f$eva$coef
    if (any(!is.finite(cf)) || any(cf == 0.1278433) || any(!is.finite(f$dp[c("lk", "df1", "df2", "rv")]))) { message("skip(nonfinite) ", cfg, " ", famname, " ev ", ev, " kern ", kern); next }
    nv <- f$nvc["nv"]
    xv <- f$eva$xev
    o <- if (ev == 2) seq_along(xv) else order(xv)
    a <- c(n, kern, deg, fam, nn, h, ev, cut, mg, quasi, m, acri, adpen, link, x, y, rob, w)
    trel <- 1e-8
    add <- function(fn, want, rel = trel, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = rel, abs = abs)
    glob <- quasi == 1 && fam %in% c(7, 8)
    add("nv", nv, 0, 0)
    add("vx", wsum(xv[o])); add("vh", wsum(cf[o, 10]))
    add("vc0", wsum(cf[o, 1])); add("vc1", wsum(cf[o, 2]))
    nab <- 1e-6
    add("vn0", wsum(cf[o, 3]), 1e-6, nab); add("vn1", wsum(cf[o, 4]), 1e-6, nab)
    add("vt0", wsum(cf[o, 5]), 1e-6, nab); add("vt1", wsum(cf[o, 6]), 1e-6, nab)
    add("vl0", wsum(cf[o, 7])); add("vl1", wsum(cf[o, 8])); add("vl2", wsum(cf[o, 9]))
    add("fit", wsum(as.numeric(fitted(f))))
    dp <- f$dp
    if (!glob) {
      add("lk", dp["lk"]); add("df0", dp["df1"]); add("df1", dp["df2"]); add("rv", dp["rv"])
      add("gcv", -2 * n * dp["lk"] / (n - dp["df1"])^2)
      add("cp", -2 * dp["lk"] - n + 2 * dp["df1"])
      add("aic", -2 * dp["lk"] + 2 * dp["df1"])
    }
    if (ev != 2) {
      nx <- seq(min(x), max(x), length = m)
      add("pred", wsum(as.numeric(predict(f, nx))))
      for (b in c("global", "local", "prediction")) {
        if (glob && b != "local") next
        pr <- predict(f, nx, band = b)
        add(c(global = "seg", local = "sel", prediction = "sep")[[b]], wsum(as.numeric(pr$se.fit)))
      }
    }
  }
  cases
}
set.seed(20271101)
emit("locfit_more", "locfit", list(gen(1:45, FALSE)))
set.seed(20271102)
emit("locfit_mindex", "locfit", list(gen(1:30, TRUE)))
