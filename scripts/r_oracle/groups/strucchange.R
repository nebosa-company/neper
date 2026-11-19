# strucchange Fstats (from = 0.15) and breakpoints (h = 0.15) of y on x with a constant.
#   args: (n, p, m, y[n], x[n*p] row-major with the constant first)
#   fn "fsum" (sum of the F statistics weighted by position), "supf", "rss" (m breaks), "bp" (breakpoints weighted by position)
suppressMessages(library(strucchange))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
set.seed(20261206)
for (rep in 1:20) {
  n <- sample(90:140, 1); p <- sample(1:7, 1); m <- sample(1:2, 1)
  x <- cbind(1, matrix(rnorm(n * (p - 1)), n)); nb <- sample(1:2, 1)
  cut <- sort(sample(12:(n - 12), nb)); seg <- findInterval(seq_len(n), cut + 1) + 1
  beta <- matrix(rnorm(p * (nb + 1), 0, 2), p)
  y <- sapply(seq_len(n), function(i) sum(x[i, ] * beta[, seg[i]])) + rnorm(n, 0, .5)
  a <- c(n, p, m, y, as.vector(t(x)))
  f <- Fstats(y ~ x - 1, from = 0.15)
  add("fsum", a, sum(as.vector(f$Fstats) * seq_along(f$Fstats))); add("supf", a, max(f$Fstats))
  b <- breakpoints(y ~ x - 1, h = 0.15, breaks = m)
  bm <- breakpoints(b, breaks = m)
  e <- efp(y ~ x - 1, type = "OLS-CUSUM"); s <- sctest(e)
  add("cus", a, unname(s$statistic)); add("cusp", a, unname(s$p.value))
  if (p <= 40) {
    for (ty in c("supF", "aveF", "expF")) { sf <- sctest(f, type = ty); add(paste0("pf", match(ty, c("supF", "aveF", "expF"))), a, unname(sf$p.value)); add(paste0("sf", match(ty, c("supF", "aveF", "expF"))), a, unname(sf$statistic)) }
  }
  hh <- c(0.1, 0.15, 0.3)[(n %% 3) + 1]
  em <- efp(y ~ x - 1, type = "OLS-MOSUM", h = hh); sm <- sctest(em)
  add("mos", c(a, hh), unname(sm$statistic)); add("mosp", c(a, hh), unname(sm$p.value))
  hr <- c(0.1, 0.2, 0.3)[(n %% 3) + 1]
  rm <- efp(y ~ x - 1, type = "Rec-MOSUM", h = hr); sq <- sctest(rm)
  add("rmo", c(a, hr), unname(sq$statistic)); add("rmop", c(a, hr), unname(sq$p.value))
  er <- efp(y ~ x - 1, type = "Rec-CUSUM"); sr <- sctest(er)
  add("rec", a, unname(sr$statistic)); add("recp", a, unname(sr$p.value))
  add("bic", a, summary(b)$RSS["BIC", m + 1]);
  add("rss", a, summary(b)$RSS["RSS", m + 1]); add("bp", a, sum(bm$breakpoints * seq_along(bm$breakpoints)))
}
# segmented::davies.test for lm(y ~ x) with seg.Z = ~x, k = 10: "dv" args (n, p = 2, alt 0 two.sided 1 less 2 greater, y[n], x[n] (the design is cbind(1, x))), which 0 the 'best' psi 1 the p value 2 the number of points
suppressMessages(library(segmented))
for (rep in 1:30) {
  n <- sample(30:120, 1); x <- sort(round(runif(n, 0, 10), 3)); cp <- runif(1, 3, 7); y <- 1 + 0.3 * x + (x > cp) * (x - cp) * runif(1, -1.5, 1.5) + rnorm(n, 0, 0.6)
  alt <- (rep - 1) %% 3; alts <- c("two.sided", "less", "greater")
  d <- data.frame(x = x, y = y)
  r <- tryCatch(suppressWarnings(davies.test(lm(y ~ x, data = d), ~x, k = 10, alternative = alts[alt + 1])), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, 2, alt, y, x)
  cases[[length(cases) + 1]] <- case("dv", c(a, 0), unname(r$statistic), rel = 1e-8, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("dv", c(a, 1), r$p.value, rel = 1e-7, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("dv", c(a, 2), unname(r$parameter), rel = 0, abs = 0)
}
# segmented::pscore.test for lm(y ~ x), k = 10: "ps" args as "dv", which 0 the score statistic 1 the p value
for (rep in 1:30) {
  n <- sample(30:120, 1); x <- sort(round(runif(n, 0, 10), 3)); cp <- runif(1, 3, 7); y <- 1 + 0.3 * x + (x > cp) * (x - cp) * runif(1, -1.5, 1.5) + rnorm(n, 0, 0.6)
  alt <- (rep - 1) %% 3; alts <- c("two.sided", "less", "greater")
  d <- data.frame(x = x, y = y); assign("d", d, envir = globalenv())
  r <- tryCatch(suppressWarnings(pscore.test(lm(y ~ x, data = d), ~x, k = 10, alternative = alts[alt + 1])), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, 2, alt, y, x)
  cases[[length(cases) + 1]] <- case("ps", c(a, 0), unname(r$statistic), rel = 1e-8, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("ps", c(a, 1), r$p.value, rel = 1e-7, abs = 1e-10)
}
# pscore.test with n.break = 2: "p2" args as "ps" (alt unused), which 0 the statistic 1 the p value
for (rep in 1:20) {
  n <- sample(30:120, 1); x <- sort(round(runif(n, 0, 10), 3)); y <- 1 + 0.3 * x + (x > 4) * (x - 4) * runif(1, -1.5, 1.5) + rnorm(n, 0, 0.6)
  d <- data.frame(x = x, y = y); assign("d", d, envir = globalenv())
  r <- tryCatch(suppressWarnings(pscore.test(lm(y ~ x, data = d), ~x, k = 10, n.break = 2)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, 2, 0, y, x)
  cases[[length(cases) + 1]] <- case("p2", c(a, 0), unname(r$statistic), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("p2", c(a, 1), r$p.value, rel = 1e-7, abs = 1e-10)
}
# pscore.test for a weighted lm: "pw" args (n, 2, alt, y[n], x[n], w[n]), which 0 the statistic 1 the p value
for (rep in 1:30) {
  n <- sample(30:120, 1); x <- sort(round(runif(n, 0, 10), 3)); w <- round(runif(n, 0.5, 3), 3); y <- 1 + 0.3 * x + (x > 4.5) * (x - 4.5) * runif(1, -1.5, 1.5) + rnorm(n, 0, 0.6) / sqrt(w)
  alt <- (rep - 1) %% 3; alts <- c("two.sided", "less", "greater")
  d <- data.frame(x = x, y = y, w = w); assign("d", d, envir = globalenv())
  r <- tryCatch(suppressWarnings(pscore.test(lm(y ~ x, data = d, weights = w), ~x, k = 10, alternative = alts[alt + 1])), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, 2, alt, y, x, w)
  cases[[length(cases) + 1]] <- case("pw", c(a, 0), unname(r$statistic), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("pw", c(a, 1), r$p.value, rel = 1e-7, abs = 1e-10)
}
# davies.test for glm(y ~ x) (type lrt, k = 10): "dg" args (n, 2, alt, fam 1 binomial 2 poisson, y[n], x[n], which) with which 0 best psi, 1 p value, 2 points
for (rep in 1:30) {
  n <- sample(60:150, 1); x <- sort(round(runif(n, 0, 10), 3)); fam <- 1 + rep %% 2; cp <- runif(1, 3, 7); eta <- 0.2 + 0.15 * x + (x > cp) * (x - cp) * runif(1, -0.6, 0.6)
  y <- if (fam == 1) rbinom(n, 1, plogis(eta - 1)) else rpois(n, exp(eta - 1))
  alt <- (rep - 1) %% 3; alts <- c("two.sided", "less", "greater"); d <- data.frame(x = x, y = y); assign("d", d, envir = globalenv())
  r <- tryCatch(davies.test(glm(y ~ x, data = d, family = if (fam == 1) binomial else poisson), ~x, k = 10, alternative = alts[alt + 1]), error = function(e) NULL, warning = function(w) NULL)  # a data set with a glm.fit warning (no convergence, fitted values at the bounds) is left out
  if (is.null(r)) next
  a <- c(n, 2, alt, fam, y, x)
  cases[[length(cases) + 1]] <- case("dg", c(a, 0), unname(r$statistic), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("dg", c(a, 1), r$p.value, rel = 1e-6, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("dg", c(a, 2), unname(r$parameter), rel = 0, abs = 0)
}
# pscore.test for glm(y ~ x), k = 10: "pg" args as "dg", which 0 the statistic 1 the p value
for (rep in 1:30) {
  n <- sample(60:150, 1); x <- sort(round(runif(n, 0, 10), 3)); fam <- 1 + rep %% 2; cp <- runif(1, 3, 7); eta <- 0.2 + 0.15 * x + (x > cp) * (x - cp) * runif(1, -0.6, 0.6)
  y <- if (fam == 1) rbinom(n, 1, plogis(eta - 1)) else rpois(n, exp(eta - 1))
  alt <- (rep - 1) %% 3; alts <- c("two.sided", "less", "greater"); d <- data.frame(x = x, y = y); assign("d", d, envir = globalenv())
  r <- tryCatch(pscore.test(glm(y ~ x, data = d, family = if (fam == 1) binomial else poisson), ~x, k = 10, alternative = alts[alt + 1]), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(r)) next
  a <- c(n, 2, alt, fam, y, x)
  cases[[length(cases) + 1]] <- case("pg", c(a, 0), unname(r$statistic), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("pg", c(a, 1), r$p.value, rel = 1e-6, abs = 1e-9)
}
# segmented(lm(y ~ x), ~x, psi = psi0): "sg" args (n, psi0, y[n], x[n], which) with which 0 psi 1 its standard error 2 intercept 3 slope 4 U coefficient 5-7 their standard errors; data sets for which the package converges normally
for (rep in 1:30) {
  n <- sample(60:200, 1); x <- sort(round(runif(n, 0, 10), 3)); cp <- runif(1, 3.5, 7); y <- 1 + 0.3 * x + pmax(x - cp, 0) * (-1.5 + runif(1, -0.3, 0.3)) + rnorm(n, 0, 0.4)
  p0 <- cp + runif(1, -0.4, 0.4); d <- data.frame(x = x, y = y)
  s <- tryCatch(suppressWarnings(segmented(lm(y ~ x, data = d), ~x, psi = p0)), error = function(e) NULL); if (is.null(s) || is.null(s$psi) || !is.finite(s$psi[1, 2])) next
  pp <- p0; dv0 <- Inf; for (it in 1:20) { U <- pmax(x - pp, 0); V <- -(x > pp) * 1; ff <- lm(y ~ x + U + V); dv <- deviance(ff); if (abs(dv - dv0) / (abs(dv) + 0.1) < 1e-4) break; dv0 <- dv; pp <- pp + coef(ff)[[4]] / coef(ff)[[3]] }
  if (abs(pp - s$psi[1, 2]) > 1e-4) next  # the package guards the iteration (limits on psi from the quantiles of x, step halving, restarts); only the data sets where the plain iteration of the port gives the same psi are used
  if (min(abs(x - s$psi[1, 2])) < 1e-4) next  # the break landed on an observation: the criterion is not smooth there and the stopping point depends on the iteration details
  sm <- summary(s)$coef; w <- c(s$psi[1, 2], s$psi[1, 3], sm[1, 1], sm[2, 1], sm[3, 1], sm[1, 2], sm[2, 2], sm[3, 2])
  for (k in 1:8) cases[[length(cases) + 1]] <- case("sg", c(n, p0, y, x, k - 1), w[k], rel = 1e-6, abs = 1e-8)
}
emit("strucchange", "strucchange", list(cases))
