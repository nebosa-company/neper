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
    if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("d", c(al, be, ga, de, x), d, rel = 1e-9, abs = 1e-14)
  }
}
for (rep in 1:60) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (x in de + ga * c(rnorm(2, 0, 1.5), runif(1, 0.05, 6) * c(-1, 1)[sample(1:2, 1)])) {
    pv <- suppressWarnings(pstable(x, al, be, ga, de, silent = TRUE))
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("p", c(al, be, ga, de, x), pv, rel = 1e-9, abs = 1e-12)
  }
}
for (rep in 1:25) {
  al <- c(runif(1, 0.5, 0.98), runif(1, 1.05, 1.95))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.9, 0.9))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (pp in runif(2, 0.05, 0.95)) {
    qv <- tryCatch(suppressWarnings(qstable(pp, al, be, ga, de)), error = function(e) NA_real_)
    if (is.finite(qv)) cases[[length(cases) + 1]] <- case("q", c(al, be, ga, de, pp), qv, rel = 1e-9, abs = 1e-10)
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
    if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("d", c(1, be, ga, de, x), d, rel = 1e-9, abs = 1e-14)
    pv <- suppressWarnings(pstable(x, 1, be, ga, de, silent = TRUE))
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("p", c(1, be, ga, de, x), pv, rel = 1e-9, abs = 1e-12)
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
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("pe", c(al, be, ga, de, x, as.numeric(lw), as.numeric(lg)), pv, rel = 1e-9, abs = 1e-11)
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
    if (is.finite(d) && d > 0) cases[[length(cases) + 1]] <- case("d", c(al, be, ga, de, x), d, rel = 1e-9, abs = 1e-18)
  }
}
# alpha near 1 with beta near 1 far in the lower tail: the integral underflows and R answers dPareto (checked per case against stabledist:::dPareto), so c_stable_tail decides
for (al in c(0.999, 1.0005, 1.001, 1.003, 1.01, 1.03, 1.1)) for (be in c(0.9, 0.99, 0.999)) for (x in c(-1e10, -1e12, -1e14)) {
  ga <- 1.3; de <- 0.4; xx <- de + ga * x
  d <- suppressWarnings(dstable(xx, al, be, ga, de))
  pr <- stabledist:::dPareto(x, al, be) / ga
  if (is.finite(d) && d > 0 && abs(d - pr) <= 1e-13 * pr) cases[[length(cases) + 1]] <- case("d", c(al, be, ga, de, xx), d, rel = 1e-9, abs = 1e-30)
}
# pm = 1 and pm = 2: args (alpha, beta, gamma, delta, x, pm) under "dpm" and "ppm"
for (rep in 1:25) {
  al <- c(runif(1, 0.4, 0.98), runif(1, 1.02, 1.95))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.95, 0.95))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (pm in 1:2) {
    x <- de + ga * rnorm(1, 0, 1.5)
    d <- tryCatch(dstable(x, al, be, ga, de, pm = pm), error = function(e) NA_real_)
    if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("dpm", c(al, be, ga, de, x, pm), d, rel = 1e-9, abs = 1e-12)
    pv <- tryCatch(suppressWarnings(pstable(x, al, be, ga, de, pm = pm, silent = TRUE)), error = function(e) NA_real_)
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("ppm", c(al, be, ga, de, x, pm), pv, rel = 1e-9, abs = 1e-10)
  }
}
# qstable with the tail and log options, alpha = 1 included: args (alpha, beta, gamma, delta, p, lower, logp) under "qe" (1e-3); the log density under "dl"
for (rep in 1:30) {
  al <- c(runif(1, 0.5, 0.98), runif(1, 1.05, 1.95), 1)[sample(1:3, 1)]
  be <- c(0, runif(1, -0.9, 0.9))[sample(1:2, 1)]
  if (al == 1 && be == 0) be <- 0.4
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  pp <- runif(1, 0.05, 0.95)
  for (lw in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) {
    pin <- if (lg) log(pp) else pp
    qv <- tryCatch(suppressWarnings(qstable(pin, al, be, ga, de, lower.tail = lw, log.p = lg)), error = function(e) NA_real_)
    if (is.finite(qv)) cases[[length(cases) + 1]] <- case("qe", c(al, be, ga, de, pin, as.numeric(lw), as.numeric(lg)), qv, rel = 1e-9, abs = 1e-10)
  }
  x <- de + ga * rnorm(1)
  dl <- dstable(x, al, be, ga, de, log = TRUE)
  if (is.finite(dl)) cases[[length(cases) + 1]] <- case("dl", c(al, be, ga, de, x), dl, rel = 1e-9, abs = 1e-10)
}
# qstable and rstable in pm = 1 and 2: "qpm" (alpha, beta, gamma, delta, p, pm) at 1e-3; "rpm" (alpha, beta, gamma, delta, seed, n, i, pm)
for (rep in 1:12) {
  al <- c(runif(1, 0.5, 0.98), runif(1, 1.05, 1.95))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.9, 0.9))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (pm in 1:2) {
    pp <- runif(1, 0.05, 0.95)
    qv <- tryCatch(suppressWarnings(qstable(pp, al, be, ga, de, pm = pm)), error = function(e) NA_real_)
    if (is.finite(qv)) cases[[length(cases) + 1]] <- case("qpm", c(al, be, ga, de, pp, pm), qv, rel = 1e-9, abs = 1e-10)
    sd0 <- sample(1:100000, 1); n <- 4
    set.seed(sd0); v <- tryCatch(rstable(n, al, be, ga, de, pm = pm), error = function(e) rep(NA_real_, n))
    for (i in seq_len(n)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("rpm", c(al, be, ga, de, sd0, n, i - 1, pm), v[i], rel = 1e-9, abs = 1e-10)
  }
}
# accuracy options, alpha != 1: "dopt" (alpha, beta, gamma, delta, x, tol, zeta.tol or -1 for NULL, subdivisions), "popt" (alpha, beta, gamma, delta, x, tol, subdivisions)
for (rep in 1:40) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  tl <- c(1e-6, 1e-7, 1e-10, 1e-13)[sample(1:4, 1)]; sb <- c(30, 200, 400, 1000)[sample(1:4, 1)]
  zt <- c(-1, 1e-3, 1e-8)[sample(1:3, 1)]
  x <- de + ga * rnorm(1, 0, 1.5)
  d <- tryCatch(dstable(x, al, be, ga, de, tol = tl, zeta.tol = if (zt < 0) NULL else zt, subdivisions = sb), error = function(e) NA_real_)
  if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("dopt", c(al, be, ga, de, x, tl, zt, sb), d, rel = 1e-9, abs = 1e-14)
  pv <- tryCatch(suppressWarnings(pstable(x, al, be, ga, de, tol = tl, subdivisions = sb, silent = TRUE)), error = function(e) NA_real_)
  if (is.finite(pv)) cases[[length(cases) + 1]] <- case("popt", c(al, be, ga, de, x, tl, sb), pv, rel = 1e-9, abs = 1e-12)
}
# qstable options: "qopt" (alpha, beta, gamma, delta, p, tol, maxiter, integ.tol, subdivisions)
for (rep in 1:25) {
  al <- c(runif(1, 0.4, 0.98), runif(1, 1.02, 1.95))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.95, 0.95))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1); pp <- runif(1, 0.05, 0.95)
  tl <- c(1e-3, 1e-6, 1e-8)[sample(1:3, 1)]; it <- c(100, 1000)[sample(1:2, 1)]
  itl <- c(1e-5, 1e-7, 1e-9)[sample(1:3, 1)]; sb <- c(100, 200, 500)[sample(1:3, 1)]
  qv <- tryCatch(suppressWarnings(qstable(pp, al, be, ga, de, tol = tl, maxiter = it, integ.tol = itl, subdivisions = sb)), error = function(e) NA_real_)
  if (is.finite(qv)) cases[[length(cases) + 1]] <- case("qopt", c(al, be, ga, de, pp, tl, it, itl, sb), qv, rel = 1e-9, abs = 1e-10)
}
# stableMode: args (alpha, beta) under "mode"
for (rep in 1:25) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(runif(1, -1, 1), runif(1, -0.999, 0.999), 1, -1)[sample(1:4, 1)]
  mv <- tryCatch(stableMode(al, be), error = function(e) NA_real_)
  if (is.finite(mv)) cases[[length(cases) + 1]] <- case("mode", c(al, be), mv, rel = 1e-9, abs = 1e-10)
}
emit("stabledist", "stabledist", list(cases))
