# DescTools CCC and CronbachAlpha. CCC args (0, ci, conf, n, x, y, j) with j 0 est, 1 lwr, 2 upr, 3 s.shift, 4 l.shift, 5 C.b; CronbachAlpha args (1, n, nc, conf, x row-major, j) with j 0 alpha, 1 lwr, 2 upr
suppressMessages(library(DescTools))
cases <- list()
set.seed(20262401)
for (rep in 1:15) {
  n <- sample(15:60, 1); x <- rnorm(n, 2, 1.5); y <- 0.8 * x + rnorm(n, 0.3, 1)
  for (ci in c("z-transform", "asymptotic")) {
    r <- CCC(x, y, ci = ci, conf.level = 0.95)
    v <- c(r$rho.c$est, r$rho.c$lwr.ci, r$rho.c$upr.ci, r$s.shift, r$l.shift, r$C.b)
    for (j in 0:5) cases[[length(cases) + 1]] <- case("a", c(0, as.numeric(ci == "asymptotic"), 0.95, n, x, y, j), v[j + 1], rel = 1e-9, abs = 1e-12)
  }
  nc <- sample(3:7, 1); m <- matrix(rnorm(n * nc), n, nc) + rnorm(n)
  r <- CronbachAlpha(m, conf.level = 0.95)
  for (j in 0:2) cases[[length(cases) + 1]] <- case("a", c(1, n, nc, 0.95, as.vector(t(m)), j), as.numeric(r[j + 1]), rel = 1e-8, abs = 1e-11)
}
# MeanCI (2: sd < 0 means the sample sd), VarCI classic and Bonett (3, 4), MeanSE (5), Herfindahl (6): args (kind, n, x, extra, j)
for (rep in 1:15) {
  n <- sample(8:50, 1); x <- rexp(n, 0.5) + rnorm(n)
  r <- MeanCI(x, conf.level = 0.9); for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(2, n, x, -1, 0.9, j), as.numeric(r[j + 1]), rel = 1e-10, abs = 1e-12)
  r <- MeanCI(x, sd = 1.7, conf.level = 0.9); for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(2, n, x, 1.7, 0.9, j), as.numeric(r[j + 1]), rel = 1e-10, abs = 1e-12)
  r <- VarCI(x, conf.level = 0.9); for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(3, n, x, 0, 0.9, j), as.numeric(r[j + 1]), rel = 1e-9, abs = 1e-12)
  r <- VarCI(x, method = "bonett", conf.level = 0.9); for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(4, n, x, 0, 0.9, j), as.numeric(r[j + 1]), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("b", c(5, n, x, 0, 0, 0), MeanSE(x), rel = 1e-10, abs = 1e-13)
  sh <- abs(x) + 0.1; cnt <- sample(1:4, n, TRUE); mp <- sample(c(1, 2, 3), 1)
  cases[[length(cases) + 1]] <- case("b", c(6, n, sh, mp, 0, 0, cnt), Herfindahl(sh, cnt, mp), rel = 1e-10, abs = 1e-13)
}
# MeanCI with trim: args (7, n, x, trim, conf, j)
for (rep in 1:15) {
  n <- sample(12:60, 1); x <- rexp(n, 0.5) + rnorm(n); tr <- sample(c(0.05, 0.1, 0.2), 1)
  r <- MeanCI(x, trim = tr, conf.level = 0.95)
  for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(7, n, x, tr, 0.95, j), as.numeric(r[j + 1]), rel = 1e-9, abs = 1e-12)
}
# CohenD: one sample (8, n, x), two samples (9, nx, ny, flags, x, y) with flags 0..3 = pooled + 2 * correct
for (rep in 1:15) {
  nx <- sample(8:40, 1); ny <- sample(8:40, 1); x <- rnorm(nx, 1); y <- rnorm(ny, 0.5, 1.4)
  cases[[length(cases) + 1]] <- case("b", c(8, nx, x, 0, 0, 0), as.numeric(CohenD(x)), rel = 1e-10, abs = 1e-12)
  for (fl in 0:3) cases[[length(cases) + 1]] <- case("b", c(9, nx, ny, fl, x, y), as.numeric(CohenD(x, y, pooled = (fl %% 2) == 1, correct = fl >= 2)), rel = 1e-10, abs = 1e-12)
}
# CohenD intervals: one sample (10, n, x, conf, j), two samples (11, nx, ny, conf, x, y, j); j 0 d, 1 lwr, 2 upr at 1e-5 (uniroot tolerance)
for (rep in 1:10) {
  nx <- sample(12:40, 1); ny <- sample(12:40, 1); x <- rnorm(nx, 1); y <- rnorm(ny, 0.5, 1.4)
  r1 <- CohenD(x, conf.level = 0.95); for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(10, nx, x, 0.95, j), as.numeric(r1[j + 1]), rel = 1e-5, abs = 1e-6)
  r2 <- CohenD(x, y, conf.level = 0.95); for (j in 0:2) cases[[length(cases) + 1]] <- case("b", c(11, nx, ny, 0.95, x, y, j), as.numeric(r2[j + 1]), rel = 1e-5, abs = 1e-6)
}
# Gini with weights and the bootstrap bca interval: args (12, n, seed, R, conf, unbiased, x, w, j) with j 0 gini, 1 lwr, 2 upr
for (rep in 1:10) {
  n <- sample(8:25, 1); x <- round(rexp(n, 0.3) + 0.5, 3); w <- round(runif(n, 0.5, 3), 2); sd0 <- sample(1:100000, 1); R <- sample(c(300, 500), 1)
  ub <- sample(c(TRUE, FALSE), 1)
  set.seed(sd0); r <- suppressWarnings(Gini(x, weights = w, unbiased = ub, conf.level = 0.95, R = R, type = "bca"))
  for (j in 0:2) cases[[length(cases) + 1]] <- case("a", c(12, n, sd0, R, 0.95, as.numeric(ub), x, w, j), as.numeric(r[j + 1]), rel = 1e-8, abs = 1e-10)
}
emit("desctools_agree", "DescTools", list(cases))
