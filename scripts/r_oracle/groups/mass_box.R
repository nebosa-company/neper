# MASS boxcox and logtrans over a grid, with and without spline interpolation.
#   "bc" / "lt" (n, p, interp, eps, m, grid[m], mode, y[n], X[n p] col-major)  mode 0 weighted sum of the loglik curve, 1 the maximiser of the curve, 2 its length, 3 the loglik at the first point
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262403)
for (rep in 1:30) {
  n <- sample(c(12, 20, 35), 1); p <- sample(1:3, 1)
  X <- cbind(1, matrix(rnorm(n * (p - 1)), n, p - 1)); y <- exp(as.vector(X %*% rnorm(p, 0, 0.5)) + rnorm(n, 0, 0.4)) + 0.1
  d <- data.frame(y = y, X[, -1, drop = FALSE]); f <- lm(y ~ ., d, y = TRUE, qr = TRUE)
  interp <- as.numeric(rep %% 2 == 0); eps <- c(1 / 50, 0.1)[rep %% 3 %/% 2 + 1]
  lam <- if (rep %% 3 == 0) seq(-2, 2, 1 / 10) else if (rep %% 3 == 1) seq(-1, 1.5, 0.25) else c(-0.5, 0, 0.01, 0.3, 1)
  r <- boxcox(f, lambda = lam, plotit = FALSE, interp = interp == 1, eps = eps)
  tail <- c(y, as.vector(X)); a <- c(n, p, interp, eps, length(lam), lam)
  add("bc", c(a, 0, tail), wsum(r$y)); add("bc", c(a, 1, tail), r$x[which.max(r$y)]); add("bc", c(a, 2, tail), length(r$y), 0, 0); add("bc", c(a, 3, tail), r$y[1])
  al <- if (rep %% 2 == 0) seq(0.5, 6, by = 0.25) - min(y) else seq(0, 3, 0.5) - min(y) + 0.01
  r2 <- logtrans(f, alpha = al, plotit = FALSE, interp = interp == 1)
  a <- c(n, p, interp, eps, length(al), al)
  add("lt", c(a, 0, tail), wsum(r2$y)); add("lt", c(a, 1, tail), r2$x[which.max(r2$y)]); add("lt", c(a, 2, tail), length(r2$y), 0, 0); add("lt", c(a, 3, tail), r2$y[1])
}

# every output of the curve for one fit: the design is the qr's, y the fit's response
emit_all <- function(f, X, lam, al, interp, eps) {
  y <- f$y; n <- length(y); p <- ncol(X); tail <- c(y, as.vector(X))
  for (kind in c("bc", "lt")) {
    r <- if (kind == "bc") boxcox(f, lambda = lam, plotit = FALSE, interp = interp == 1, eps = eps) else logtrans(f, alpha = al, plotit = FALSE, interp = interp == 1)
    g <- if (kind == "bc") lam else al
    a <- c(n, p, interp, eps, length(g), g)
    add(kind, c(a, 0, tail), wsum(r$y)); add(kind, c(a, 1, tail), r$x[which.max(r$y)]); add(kind, c(a, 2, tail), length(r$y), 0, 0); add(kind, c(a, 3, tail), r$y[1])
    add(kind, c(a, 4, tail), wsum(r$x)); add(kind, c(a, 5, tail), r$y[length(r$y)]); add(kind, c(a, 6, tail), max(r$y)); add(kind, c(a, 7, tail), sum(r$y^2))
  }
}
for (rep in 1:24) {
  n <- sample(c(15, 28, 50), 1); p <- sample(1:3, 1)
  d <- data.frame(a = round(rnorm(n), 3), b = round(runif(n), 3), g = factor(sample(c("u", "v", "w"), n, TRUE)))
  assign("d", d, globalenv()); d$y <- round(exp(0.4 * d$a + 0.3 * (d$g == "v") + rnorm(n, 0, 0.35)) + 0.2, 4)
  lam <- if (rep %% 3 == 0) seq(-2, 2, 1 / 10) else if (rep %% 3 == 1) seq(-1.5, 1.5, 0.25) else c(-0.7, 0, 0.015, 0.4, 1.2)
  interp <- as.numeric(rep %% 2 == 0); eps <- c(1 / 50, 0.1, 1e-3)[rep %% 3 + 1]
  fo <- list(y ~ a, y ~ a + b, y ~ a + g, y ~ g, y ~ a * g)[[(rep - 1) %% 5 + 1]]
  assign("d", d, globalenv()); al <- seq(0.4, 5, length.out = 9) - min(d$y)
  if (rep %% 4 == 0) {            # weighted lm
    w <- round(runif(n, 0.3, 3), 2)
    f <- lm(fo, d, weights = w, y = TRUE, qr = TRUE)
    X <- sqrt(w) * model.matrix(f)
  } else if (rep %% 4 == 1) {     # formula interface with a subset (boxcox.formula and logtrans on the lm)
    sub <- sort(sample(n, n - 4)); f <- lm(fo, d, subset = sub, y = TRUE, qr = TRUE); X <- model.matrix(f)
    r1 <- do.call(boxcox, list(fo, data = d, subset = sub, lambda = lam, plotit = FALSE, interp = interp == 1, eps = eps))
    r2 <- boxcox(f, lambda = lam, plotit = FALSE, interp = interp == 1, eps = eps)
    stopifnot(identical(r1, r2))
  } else if (rep %% 4 == 2) {     # aov object
    f0 <- aov(y ~ g, d); f <- update(f0, y = TRUE, qr = TRUE); X <- model.matrix(f); fo <- NULL
    r1 <- boxcox(f0, lambda = lam, plotit = FALSE, interp = interp == 1, eps = eps); r2 <- boxcox(f, lambda = lam, plotit = FALSE, interp = interp == 1, eps = eps)
    stopifnot(identical(r1, r2))
  } else { f <- lm(fo, d, y = TRUE, qr = TRUE); X <- model.matrix(f) }
  emit_all(f, X, lam, al, interp, eps)
}
emit("mass_box", "MASS", list(cases))
