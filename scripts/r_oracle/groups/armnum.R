# armnum: the numeric building blocks arm's fits need to match R to the last bit.
#   "ldsum" (which 0 sum 1 mean 2 var 3 colMeans, n, x): the long double accumulation of R's sum, mean, var and colMeans
#   "libm" (which, x[, df]) with which 0 exp 1 log 2 x^3 3 x^1.5 4 pnorm 5 dnorm 6 atan 7 pcauchy 8 dcauchy 9 qcauchy 10 qnorm 11 log dt(x, df) 12 log1p 16 exp 17 log 18 tan 19 Gumbel cdf:
#   the functions of armglm, armpolr, armdt, armtan and armx87 compared with R's own to the last bit (exp and log as the x87 runtime of R on Windows rounds them, tan and atan the C runtime's)
suppressMessages(library(arm))
cases <- list()
set.seed(20262400)
for (rep in 1:80) {
  n <- sample(2:40, 1); x <- switch(rep %% 4 + 1, rnorm(n), rnorm(n) * 10^sample(-3:3, n, TRUE), round(runif(n), 3), rnorm(n, 100, 0.01))
  cases[[length(cases) + 1]] <- case("ldsum", c(0, n, x), sum(x), rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("ldsum", c(1, n, x), mean(x), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("ldsum", c(2, n, x), var(x), rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("ldsum", c(3, n, x), colMeans(matrix(x, ncol = 1)), rel = 0, abs = 0)
}
for (v in c(rnorm(40, 0, 2), runif(30, 0.01, 8))) {
  cases[[length(cases) + 1]] <- case("libm", c(0, v), exp(v), rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("libm", c(4, v), pnorm(v), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("libm", c(5, v), dnorm(v), rel = 0, abs = 0)
}
for (v in runif(70, 0.01, 8)) {
  cases[[length(cases) + 1]] <- case("libm", c(1, v), log(v), rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("libm", c(2, v), v^3, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("libm", c(3, v), v^1.5, rel = 0, abs = 0)
}
# which 6 atan, 7 pcauchy, 8 dcauchy, 9 qcauchy (x a probability), 10 qnorm (x a probability), 11 pnorm of the standard normal with lower.tail = FALSE
for (v in c(rnorm(60, 0, 3), runif(40, -0.99, 0.99), rnorm(20, 0, 30))) {
  cases[[length(cases) + 1]] <- case("libm", c(6, v), atan(v), rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("libm", c(7, v), pcauchy(v), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("libm", c(8, v), dcauchy(v), rel = 0, abs = 0)
}
for (v in c(runif(300), (1:8) / 9, (0.5 + 1:6) / 7, 0.25, 0.75, 0.125, 0.875, 1/6, 5/6, 0.5, 0.01, 0.99)) {
  cases[[length(cases) + 1]] <- case("libm", c(9, v), qcauchy(v), rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("libm", c(10, v), qnorm(v), rel = 0, abs = 0)
}
# which 11 log dt(x, df) with df = args[3]
for (df in c(1, 3, 5, 7, 2.5, 4)) for (v in c(rnorm(40, 0, 1.2), runif(20, -0.3, 0.3), rnorm(10, 0, 8))) cases[[length(cases) + 1]] <- case("libm", c(11, v, df), dt(v, df, log = TRUE), rel = 0, abs = 0)
# which 12 log1p(x)
for (v in c(runif(200, 0, 0.3), rnorm(50, 0, 0.01), runif(50, 0.3, 5), 10^-(5:12) * 1.37)) cases[[length(cases) + 1]] <- case("libm", c(12, v), log1p(v), rel = 0, abs = 0)
# which 16 exp and 17 log through the x87 style rounding of armx87, 18 tan (C runtime), each against R's
set.seed(20262411)
vv <- c(rnorm(1500, 0, 3), runif(800, -1, 1), -runif(700, 0, 40), rnorm(1000, -1.9, 0.2))
for (v in vv) { cases[[length(cases) + 1]] <- case("libm", c(16, v), exp(v), rel = 0, abs = 0); if (v != 0) cases[[length(cases) + 1]] <- case("libm", c(17, abs(v)), log(abs(v)), rel = 0, abs = 0) }
for (v in abs(vv[1:2000]) %% 1.5) cases[[length(cases) + 1]] <- case("libm", c(18, v), tan(v), rel = 0, abs = 0)
# which 19 the Gumbel cdf exp(-exp(-q)) of arm
for (q in rnorm(1500, 0.5, 1.2)) cases[[length(cases) + 1]] <- case("libm", c(19, q), arm:::pgumbel(q), rel = 0, abs = 0)
emit("armnum", "arm", list(cases))
