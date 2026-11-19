# sm: h.select(x, method = "cv"), one variable, unbinned. Args: (n, x[n]) or hcvreg (n, x[n], y[n]).
suppressMessages(library(sm))
cases <- list()
set.seed(20262330)
for (rep in 1:30) {
  n <- sample(20:90, 1); x <- if (rep %% 2 == 0) rnorm(n) else c(rnorm(n %/% 2), rnorm(n - n %/% 2, 3, 0.6))
  r <- tryCatch(h.select(x, method = "cv"), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hcvsel", c(n, x), r, rel = 1e-7, abs = 1e-12)
}
for (rep in 1:20) {
  n <- sample(20:90, 1); x <- rnorm(n); y <- sin(x) + rnorm(n, 0, 0.3)
  r <- tryCatch(h.select(x, y, method = "cv"), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hcvreg", c(n, x, y), r, rel = 1e-7, abs = 1e-12)
}
for (rep in 1:20) {
  n <- sample(20:90, 1); x <- rnorm(n); y <- sin(x) + rnorm(n, 0, 0.3)
  r <- tryCatch(h.select(x, y, method = "aicc"), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("haicc", c(n, x, y), r, rel = 1e-6, abs = 1e-12)
  r <- tryCatch(h.select(x, y, method = "df", df = 5), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hdf", c(n, x, y), r, rel = 1e-6, abs = 1e-12)
}
# hse (n, h, p, x[n], y[n]): the se of sm.regression at p
for (rep in 1:20) {
  n <- sample(20:90, 1); x <- runif(n, 0, 10); y <- sin(x) + rnorm(n, 0, 0.3); h <- runif(1, 0.5, 1.5); p <- runif(1, 1, 9)
  r <- sm.regression(x, y, h = h, eval.points = p, display = "none")$se
  cases[[length(cases) + 1]] <- case("hse", c(n, h, p, x, y), r[1], rel = 1e-9, abs = 1e-12)
}
# hbin (n, nbins, x[n], y[n]): m, then the index-weighted sums of the bin x, freq, means, devs (four cases)
for (rep in 1:15) {
  n <- sample(50:300, 1); nb <- sample(5:20, 1); x <- rnorm(n); y <- x^2 + rnorm(n)
  b <- binning(x, y, nbins = nb); w <- seq_along(b$x)
  a <- c(n, nb, x, y)
  cases[[length(cases) + 1]] <- case("hbm", a, length(b$x), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("hbx", a, sum(b$x * w), rel = 1e-12, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("hbf", a, sum(b$x.freq * w), rel = 1e-12, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("hbmean", a, sum(b$means * w), rel = 1e-10, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("hbdev", a, sum(b$devs * w), rel = 1e-9, abs = 1e-12)
}
# hbreg (n, nbins, h, p, x[n], y[n]): sm.regression on nbins bins
for (rep in 1:15) {
  n <- sample(100:400, 1); nb <- sample(8:25, 1); x <- runif(n, 0, 10); y <- sin(x) + rnorm(n, 0, 0.3); h <- runif(1, 0.5, 1.5); p <- runif(1, 1, 9)
  r <- sm.regression(x, y, h = h, eval.points = p, display = "none", nbins = nb)$estimate
  cases[[length(cases) + 1]] <- case("hbreg", c(n, nb, h, p, x, y), r[1], rel = 1e-9, abs = 1e-12)
}
# hbden (n, nbins, h, p, x[n]): sm.density on nbins bins
for (rep in 1:15) {
  n <- sample(100:400, 1); nb <- sample(8:25, 1); x <- rnorm(n); h <- runif(1, 0.2, 0.8); p <- runif(1, -1, 1)
  r <- sm.density(x, h = h, eval.points = p, display = "none", nbins = nb)$estimate
  cases[[length(cases) + 1]] <- case("hbden", c(n, nb, h, p, x), r[1], rel = 1e-9, abs = 1e-12)
}
# hbsel (n, nbins, x[n]): h.select(x, method = "cv", nbins = nbins)
for (rep in 1:15) {
  n <- sample(100:300, 1); nb <- sample(8:25, 1); x <- rnorm(n)
  r <- tryCatch(h.select(x, method = "cv", nbins = nb), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hbsel", c(n, nb, x), r, rel = 1e-6, abs = 1e-12)
}
# hbrcv / hbrdf / hbraicc (n, nbins, x[n], y[n]): h.select(x, y, method, nbins = nbins), df = 5
for (rep in 1:10) {
  n <- sample(100:300, 1); nb <- sample(10:25, 1); x <- rnorm(n); y <- sin(x) + rnorm(n, 0, 0.3)
  for (m in c("df", "aicc")) {
    r <- tryCatch(h.select(x, y, method = m, nbins = nb, df = 5), error = function(e) NULL)
    if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case(paste0("hbr", m), c(n, nb, x, y), r, rel = 1e-6, abs = 1e-12)
  }
}
# hanc (n, h, x[n], y[n], group[n]): the p-value of sm.ancova(model = "equal") on one covariate
for (rep in 1:20) {
  n <- sample(20:50, 1); x <- runif(n, 0, 10); gr <- sample(1:2, n, TRUE); if (length(unique(gr)) < 2) next
  y <- sin(x) + 0.3 * (gr - 1) * (rep %% 2) + rnorm(n, 0, 0.3); h <- runif(1, 0.6, 1.5)
  r <- tryCatch(sm.ancova(x, y, gr, h = h, model = "equal", display = "none", verbose = 0)$p, error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hanc", c(n, h, x, y, gr), r, rel = 1e-7, abs = 1e-10)
}
# hanp: the same layout with model = "parallel"
for (rep in 1:20) {
  n <- sample(20:50, 1); x <- runif(n, 0, 10); gr <- sample(1:3, n, TRUE); if (length(unique(gr)) < 3) next
  y <- sin(x) + 0.3 * (gr - 1) + rnorm(n, 0, 0.3) + (rep %% 2) * 0.2 * x * (gr == 2); h <- runif(1, 0.6, 1.5)
  r <- tryCatch(sm.ancova(x, y, gr, h = h, model = "parallel", display = "none", verbose = 0)$p, error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hanp", c(n, h, x, y, gr), r, rel = 1e-6, abs = 1e-9)
}
# hsv (n, h, hv, p, e, x[n], y[n], status[n]): sm.survival at one evaluation point
for (rep in 1:30) {
  n <- sample(30:80, 1); x <- runif(n, 0, 10); y <- round(rexp(n, 0.3 + 0.1 * x), 3) + 0.1; status <- rbinom(n, 1, 0.7); if (sum(status) < 5) next
  h <- runif(1, 0.8, 2); hv <- runif(1, 0.03, 0.12); p <- c(0.25, 0.5, 0.75)[rep %% 3 + 1]; e <- runif(1, 2, 8)
  r <- tryCatch(as.numeric(sm.survival(x, y, status, h = h, hv = hv, p = p, eval.points = e, display = "none")$estimate), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hsv", c(n, h, hv, p, e, x, y, status), r, rel = 1e-8, abs = 1e-10)
}
# hnoe / hlin / hq0 / hq1 (n, h, x[n], y[n]): the reference-band test of sm.regression, model no.effect (p, q.squared) and linear (p, q.squared)
for (rep in 1:30) {
  n <- sample(20:60, 1); x <- runif(n, 0, 10); y <- (rep %% 2) * sin(x) + 0.1 * x + rnorm(n, 0, 0.4); h <- runif(1, 0.6, 1.8)
  for (m in c("no.effect", "linear")) {
    r <- tryCatch(sm.regression(x, y, h = h, model = m, display = "none", verbose = 0), error = function(e) NULL)
    if (is.null(r)) next
    cases[[length(cases) + 1]] <- case(if (m == "linear") "hlin" else "hnoe", c(n, h, x, y), r$p, rel = 1e-7, abs = 1e-10)
    cases[[length(cases) + 1]] <- case(if (m == "linear") "hql" else "hqn", c(n, h, x, y), r$q.squared, rel = 1e-9, abs = 1e-12)
  }
}
# hc2 (n, which, x[n], y[n]): h.select(cbind(x, y), method = "cv") (n <= 100, scaled structure), bandwidth 1 or 2
for (rep in 1:20) {
  n <- sample(30:90, 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n, 0, 0.8)
  r <- tryCatch(h.select(cbind(x, y), method = "cv"), error = function(e) NULL)
  if (!is.null(r) && all(is.finite(r))) for (w in 1:2) cases[[length(cases) + 1]] <- case("hc2", c(n, w - 1, x, y), r[w], rel = 1e-6, abs = 1e-10)
}
# hc2c (n, 0, x[n], y[n]): the common structure
for (rep in 1:20) {
  n <- sample(30:90, 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n, 0, 0.8)
  r <- tryCatch(h.select(cbind(x, y), method = "cv", structure.2d = "common"), error = function(e) NULL)
  if (!is.null(r) && all(is.finite(r))) cases[[length(cases) + 1]] <- case("hc2c", c(n, 0, x, y), r[1], rel = 1e-6, abs = 1e-10)
}
# hc2s (n, which, x[n], y[n]): the separate structure
for (rep in 1:20) {
  n <- sample(30:90, 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n, 0, 0.8)
  r <- tryCatch(h.select(cbind(x, y), method = "cv", structure.2d = "separate"), error = function(e) NULL)
  if (!is.null(r) && all(is.finite(r))) for (w in 1:2) cases[[length(cases) + 1]] <- case("hc2s", c(n, w - 1, x, y), r[w], rel = 1e-6, abs = 1e-10)
}
# hr2 (n, kind 0 cv 1 df 2 aicc, which, x[n], y[n], z[n]): h.select(cbind(x, y), z, method) scaled structure, df 12 by default
for (rep in 1:30) {
  n <- sample(40:90, 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n, 0, 0.8); z <- sin(x) + 0.5 * y + rnorm(n, 0, 0.3)
  for (kd in 0:2) {
    r <- tryCatch(h.select(cbind(x, y), z, method = c("cv", "df", "aicc")[kd + 1]), error = function(e) NULL)
    if (!is.null(r) && all(is.finite(r))) for (w in 1:2) cases[[length(cases) + 1]] <- case("hr2", c(n, kd, w - 1, x, y, z), r[w], rel = 1e-5, abs = 1e-9)
  }
}
emit("sm_hsel", "sm", list(cases))
