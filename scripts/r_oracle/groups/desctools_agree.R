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
emit("desctools_agree", "DescTools", list(cases))
