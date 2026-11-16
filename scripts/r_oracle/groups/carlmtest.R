# car, lmtest, sandwich: vcovHC (HC0 to HC4), dwtest, studentized bptest and vif of a linear model.
#   args: (n, p, y[n]..., X row-major n by p with the intercept column...)   fn "hc0" .. "hc4" (sum of diag(vcovHC) * position), "dw", "bp", "vif" (sum of vif * position)
suppressMessages({library(car); library(lmtest); library(sandwich)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-12)
set.seed(20261228)
for (rep in 1:12) {
  n <- sample(20:70, 1); k <- sample(2:4, 1)
  X <- matrix(rnorm(n * k), n, k); for (j in 2:k) X[, j] <- X[, j] + 0.6 * X[, j - 1]
  y <- 1 + X %*% (1:k / 2) + rnorm(n) * (1 + abs(X[, 1])); colnames(X) <- paste0("v", 1:k)
  d <- data.frame(y = as.vector(y), X); m <- lm(y ~ ., d)
  des <- cbind(1, X); a <- c(n, k + 1, as.vector(y), as.vector(t(des)))
  for (t in 0:4) { dv <- diag(vcovHC(m, paste0("HC", t))); add(paste0("hc", t), a, sum(dv * seq_along(dv))) }
  add("dw", a, as.numeric(dwtest(m)$statistic)); add("bp", a, as.numeric(bptest(m)$statistic))
  add("bpc", a, as.numeric(bptest(m, studentize = FALSE)$statistic)); add("reset", a, as.numeric(resettest(m)$statistic)); add("bpp", a, bptest(m)$p.value); g <- gqtest(m); add("gq", a, as.numeric(g$statistic)); add("gqp", a, g$p.value); add("resetp", a, resettest(m)$p.value)
  for (lg in c(2, 4)) for (ad in c(FALSE, TRUE)) { dv <- diag(NeweyWest(m, lag = lg, prewhite = FALSE, adjust = ad)); add("nw", c(a, lg, as.numeric(ad)), sum(dv * seq_along(dv))) }
  yp <- exp(as.vector(y) / 3); d2 <- data.frame(yp = yp, X); mp <- lm(yp ~ ., d2); mp$call$data <- d2; mp$call$formula <- as.formula("yp ~ .", env = list2env(list(yp = yp)));  ap <- c(n, k + 1, yp, as.vector(t(des))); for (lm0 in c(-1.5, -0.5, 0, 0.3, 1, 2)) add("bc", c(ap, lm0), boxCox(mp, lambda = lm0, plotit = FALSE)$y)
  ptl <- tryCatch(as.numeric(suppressWarnings(powerTransform(mp))$lambda), error = function(e) NA); if (is.finite(ptl)) cases[[length(cases) + 1]] <- case("pt_lambda", ap, ptl, rel = 2e-3, abs = 2e-3)
  for (ty in 1:3) { an <- if (ty == 1) anova(m) else Anova(m, type = ty); for (j in 1:k) { jj <- if (ty == 3) j + 1 else j; add("an", c(a, ty, j), an$`F value`[jj]); add("anp", c(a, ty, j), an$`Pr(>F)`[jj]) } }
  q <- sample(1:min(3, k + 1), 1); H <- matrix(round(rnorm(q * (k + 1)), 2), q, k + 1); rh <- round(rnorm(q, 0, 0.5), 2); lh <- suppressWarnings(linearHypothesis(m, H, rh)); add("lh", c(a, q, as.vector(t(H)), rh), lh$F[2]); add("lhp", c(a, q, as.vector(t(H)), rh), lh$`Pr(>F)`[2])
  nv <- ncvTest(m); add("ncv", a, nv$ChiSquare); add("ncvp", a, nv$p)
  rt <- raintest(m); add("rain", a, as.numeric(rt$statistic)); add("rainp", a, rt$p.value); ht <- harvtest(m); add("harv", a, as.numeric(ht$statistic)); add("harvp", a, ht$p.value)
  if (k >= 2) { qd <- sample(1:k, 1); m0 <- if (k == qd) lm(y ~ 1, d) else lm(y ~ ., d[, seq_len(k + 1 - qd), drop = FALSE]); a3 <- c(a, qd); lt <- lrtest(m0, m); wt <- waldtest(m0, m)
    add("lr", a3, lt$Chisq[2]); add("lrp", a3, lt$`Pr(>Chisq)`[2]); add("wf", a3, wt$F[2]); add("wfp", a3, wt$`Pr(>F)`[2]) }
  for (j in 0:k) { cm <- coeftest(m); a4 <- c(a, j); add("ct_t", a4, cm[j + 1, 3]); add("ct_p", a4, cm[j + 1, 4]) }
  for (kd in 0:4) { v <- switch(kd + 1, cooks.distance(m), rstandard(m), rstudent(m), dffits(m), hatvalues(m)); a5 <- c(a, kd); add("inf_s", a5, sum(v * seq_along(v))); add("inf_1", a5, v[1]) }
  if (k >= 2) { jt <- jtest(lm(y ~ v1, d), lm(as.formula(paste("y ~", paste0("v", 2:k, collapse = " + "))), d)); add("jt_t1", a, jt[1, 3]); add("jt_p1", a, jt[1, 4]); add("jt_t2", a, jt[2, 3]); add("jt_p2", a, jt[2, 4]) }
  for (R in c(30, 120)) { sd <- sample(1:1e6, 1); set.seed(sd); vb <- vcovBS(m, R = R); add("vbs", c(a, sd, R), sum(as.vector(t(vb)) * seq_len(length(vb)))) }
  for (ng in c(5, 10)) { nid <- max(2, n %/% ng); tm <- rep(seq_len(ng), length.out = n); id <- rep(seq_len(nid), each = ceiling(n / nid))[seq_len(n)]
    for (lg in c(-1, 1, 3)) { vp <- if (lg < 0) vcovPL(m, cluster = id, order.by = tm) else vcovPL(m, cluster = id, order.by = tm, lag = lg); dv <- diag(vp); add("vpl", c(a, lg, tm), sum(dv * seq_along(dv))) } }
  for (ord in c(1, 2, 4)) { a2 <- c(a, ord); b1 <- bgtest(m, order = ord); b2 <- bgtest(m, order = ord, type = "F"); add("bg_c", a2, as.numeric(b1$statistic)); add("bg_cp", a2, b1$p.value); add("bg_f", a2, as.numeric(b2$statistic)); add("bg_fp", a2, b2$p.value) }
  if (k >= 2) { v <- vif(m); add("vif", a, sum(v * seq_along(v))) }
}
for (rep in 1:10) {
  n <- sample(30:80, 1); ng <- sample(4:10, 1); g <- sample(seq_len(ng), n, replace = TRUE); ng <- length(unique(g)); gi <- match(g, sort(unique(g))) - 1
  k <- sample(1:3, 1); X <- matrix(rnorm(n * k), n, k); y <- 1 + X %*% rep(0.5, k) + rnorm(n) + gi / 4
  d <- data.frame(y = as.vector(y), X); m <- lm(y ~ ., d); des <- cbind(1, X); a <- c(n, k + 1, as.vector(y), as.vector(t(des)))
  for (ty in c("HC0", "HC1")) for (ca in c(FALSE, TRUE)) { dv <- diag(vcovCL(m, cluster = g, type = ty, cadjust = ca)); add("cl", c(a, ng, as.numeric(ty == "HC1"), as.numeric(ca), gi), sum(dv * seq_along(dv))) }
}
for (rep in 1:15) {
  n <- sample(20:70, 1); ng <- sample(2:4, 1); gr <- sample(0:(ng - 1), n, TRUE); ng <- length(unique(gr)); gr <- match(gr, sort(unique(gr))) - 1
  y <- rnorm(n) * (1 + gr) + gr * 0.3; if (rep %% 3 == 0) y <- rexp(n)
  for (ce in 0:1) { lt <- leveneTest(y, factor(gr), center = if (ce == 0) median else mean); add("lev", c(n, 1, y, gr, ng, ce), lt[1, "F value"]); add("levp", c(n, 1, y, gr, ng, ce), lt[1, "Pr(>F)"]) }
}
# grangertest: ("gr_f" "gr_p") args (n, 1, y[n], x[n], order)
for (rep in 1:20) {
  n <- sample(40:120, 1); x <- as.vector(arima.sim(list(ar = 0.5), n)); y <- c(0, 0.5 * x[-n]) + 0.4 * c(0, rnorm(n - 1)) + rnorm(n); ord <- sample(1:4, 1)
  gt <- suppressWarnings(grangertest(x, y, order = ord)); a <- c(n, 1, y, x, ord)
  cases[[length(cases) + 1]] <- case("gr_f", a, gt$F[2], rel = 1e-9, abs = 1e-12); cases[[length(cases) + 1]] <- case("gr_p", a, gt$`Pr(>F)`[2], rel = 1e-9, abs = 1e-12)
}
# Anova with a factor and a numeric predictor: ("ab_f" "ab_p") args (n, p, y, design row-major, start, q, type); terms: f (columns 1 .. nl - 1) and z (last column)
for (rep in 1:20) {
  n <- sample(30:90, 1); nl <- sample(3:5, 1); f <- factor(sample(seq_len(nl), n, TRUE)); if (nlevels(f) < nl) next; z <- rnorm(n); y <- as.numeric(f) * 0.4 + z * 0.7 + rnorm(n)
  des <- cbind(1, model.matrix(~ f)[, -1], z); p <- ncol(des); mm <- lm(y ~ f + z); a <- c(n, p, y, as.vector(t(des)))
  for (ty in 1:3) { an <- if (ty == 1) anova(mm) else Anova(mm, type = ty); jj <- if (ty == 3) 2:3 else 1:2; starts <- c(1, nl); qs <- c(nl - 1, 1)
    for (t in 1:2) { add("ab_f", c(a, starts[t], qs[t], ty), an$`F value`[jj[t]]); add("ab_p", c(a, starts[t], qs[t], ty), an$`Pr(>F)`[jj[t]]) } }
}
# Anova with a factor, a numeric term and their interaction: ("am_f" "am_p") args (n, p, y, design row-major, big mask[p], small mask[p], q); the masks pick the models each type compares
for (rep in 1:20) {
  n <- sample(40:100, 1); nl <- sample(2:4, 1); f <- factor(sample(seq_len(nl), n, TRUE)); if (nlevels(f) < nl) next; z <- rnorm(n); y <- as.numeric(f) * 0.4 + z * 0.7 + 0.5 * z * as.numeric(f) + rnorm(n)
  mm <- lm(y ~ f * z); des <- model.matrix(mm); p <- ncol(des); a <- c(n, p, y, as.vector(t(des))); asg <- attr(des, "assign")
  idx <- function(t) which(asg == t); all1 <- rep(1, p); mk <- function(cols) { v <- rep(0, p); v[cols] <- 1; v }
  tf <- idx(1); tz <- idx(2); tfz <- idx(3); int0 <- idx(0)
  an1 <- anova(mm); an2 <- Anova(mm, type = 2); an3 <- suppressWarnings(Anova(mm, type = 3))
  specs <- list(
    list(mk(c(int0, tf)), mk(int0), 1, an1$`F value`[1], an1$`Pr(>F)`[1], tf), list(mk(c(int0, tf, tz)), mk(c(int0, tf)), 1, an1$`F value`[2], an1$`Pr(>F)`[2], tz), list(all1, mk(c(int0, tf, tz)), 1, an1$`F value`[3], an1$`Pr(>F)`[3], tfz),
    list(mk(c(int0, tf, tz)), mk(c(int0, tz)), 2, an2$`F value`[1], an2$`Pr(>F)`[1], tf), list(mk(c(int0, tf, tz)), mk(c(int0, tf)), 2, an2$`F value`[2], an2$`Pr(>F)`[2], tz), list(all1, mk(c(int0, tf, tz)), 2, an2$`F value`[3], an2$`Pr(>F)`[3], tfz),
    list(all1, mk(setdiff(seq_len(p), tf)), 3, an3$`F value`[2], an3$`Pr(>F)`[2], tf), list(all1, mk(setdiff(seq_len(p), tz)), 3, an3$`F value`[3], an3$`Pr(>F)`[3], tz), list(all1, mk(setdiff(seq_len(p), tfz)), 3, an3$`F value`[4], an3$`Pr(>F)`[4], tfz))
  for (s in specs) { q <- length(s[[6]]); if (s[[3]] == 1 && q == 0) next; add("am_f", c(a, s[[1]], s[[2]], q), s[[4]]); add("am_p", c(a, s[[1]], s[[2]], q), s[[5]]) }
}
emit("carlmtest", "car", list(cases))
