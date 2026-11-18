# stabledist::dstable (name "d") and pstable (name "p") in the S0 parametrisation. args: (alpha, beta, gamma, delta, x)
suppressMessages(library(stabledist))
cases <- list()
set.seed(20261801)
for (rep in 1:60) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (x in de + ga * c(rnorm(2, 0, 1.5), runif(1, 0.05, 6) * c(-1, 1)[sample(1:2, 1)])) {
    d <- dstable(x, al, be, ga, de)
    if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("d", c(al, be, ga, de, x), d, rel = 1e-8, abs = 1e-14)
  }
}
for (rep in 1:60) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (x in de + ga * c(rnorm(2, 0, 1.5), runif(1, 0.05, 6) * c(-1, 1)[sample(1:2, 1)])) {
    pv <- suppressWarnings(pstable(x, al, be, ga, de, silent = TRUE))
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("p", c(al, be, ga, de, x), pv, rel = 1e-8, abs = 1e-12)
  }
}
for (rep in 1:25) {
  al <- c(runif(1, 0.5, 0.98), runif(1, 1.05, 1.95))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.9, 0.9))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (pp in runif(2, 0.05, 0.95)) {
    qv <- tryCatch(suppressWarnings(qstable(pp, al, be, ga, de)), error = function(e) NA_real_)
    if (is.finite(qv)) cases[[length(cases) + 1]] <- case("q", c(al, be, ga, de, pp), qv, rel = 1e-3, abs = 1e-4)
  }
}
# rstable: args (alpha, beta, gamma, delta, seed, n, i) -> the i-th draw (0-based) of set.seed(seed); rstable(n, alpha, beta, gamma, delta)
for (rep in 1:12) {
  al <- c(runif(1, 0.4, 0.98), runif(1, 1.02, 2))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1))[sample(1:2, 1)]
  if (rep == 1) { al <- 1; be <- 0 }
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1); sd0 <- sample(1:100000, 1); n <- 6
  set.seed(sd0); v <- rstable(n, al, be, ga, de)
  for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("r", c(al, be, ga, de, sd0, n, i - 1), v[i], rel = 1e-9, abs = 1e-12)
}
# alpha = 1 with beta != 0
for (rep in 1:20) {
  be <- c(runif(1, 0.05, 1), -runif(1, 0.05, 1))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (x in de + ga * c(rnorm(2, 0, 1.5), runif(1, 0.05, 6) * c(-1, 1)[sample(1:2, 1)])) {
    d <- dstable(x, 1, be, ga, de)
    if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("d", c(1, be, ga, de, x), d, rel = 1e-8, abs = 1e-14)
    pv <- suppressWarnings(pstable(x, 1, be, ga, de, silent = TRUE))
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("p", c(1, be, ga, de, x), pv, rel = 1e-8, abs = 1e-12)
  }
}
# pstable with lower.tail and log.p: args (alpha, beta, gamma, delta, x, lower, logp) under the name "pe"
for (rep in 1:40) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99), 1)[sample(1:3, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  if (al == 1 && be == 0) be <- 0.5
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  x <- de + ga * rnorm(1, 0, 2.5)
  for (lw in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) {
    pv <- suppressWarnings(pstable(x, al, be, ga, de, lower.tail = lw, log.p = lg, silent = TRUE))
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("pe", c(al, be, ga, de, x, as.numeric(lw), as.numeric(lg)), pv, rel = 1e-7, abs = 1e-11)
  }
}
# the small-alpha branch and the far tail (Pareto fallback): densities
for (rep in 1:20) {
  al <- c(runif(1, 0.005, 0.0199), runif(1, 0.5, 1.9))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.9, 0.9))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  xs <- if (al < 0.02) de + ga * c(0.5, -2, 30) else de + ga * c(300, -500, 4000)
  for (x in xs) {
    d <- dstable(x, al, be, ga, de)
    if (is.finite(d) && d > 0) cases[[length(cases) + 1]] <- case("d", c(al, be, ga, de, x), d, rel = 1e-7, abs = 1e-18)
  }
}
emit("stabledist", "stabledist", list(cases))
