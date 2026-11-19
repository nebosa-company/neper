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
emit("sm_hsel", "sm", list(cases))
