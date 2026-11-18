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
emit("desctools_agree", "DescTools", list(cases))
