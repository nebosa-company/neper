# kernlab ksvm solvers (C-svc, nu-svc, one-svc, eps-svr, nu-svr) on two-class / regression data, kernels vanilla, poly, rbf, tanh, laplace, anova, spline.
#   args: (n, p, ktype, svm, C, nu, svr_eps, gamma, degree, coef0, y[n], x[n*p] row-major); data arrive in ksvm's class order
#   fn "alpha" (position-weighted signed coefficients), "rho" (b), "obj", "dec" (position-weighted decision values on the training points)
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261301)
kinds <- c(0, 1, 2, 3, 5, 7, 8); svms <- c(0, 1, 2, 3, 4)
for (rep in 1:70) {
  kt <- kinds[(rep - 1) %% 7 + 1]; sv <- svms[((rep - 1) %/% 7 + (rep - 1) %% 7) %% 5 + 1]
  n <- sample(20:40, 1); p <- sample(2:4, 1)
  C <- runif(1, 0.5, 8); nu <- runif(1, 0.1, 0.5); pe <- runif(1, 0.05, 0.3)
  sg <- runif(1, 0.1, 1.2); dg <- sample(2:3, 1); off <- runif(1, 0, 1)
  kn <- switch(as.character(kt), "0" = vanilladot(), "1" = polydot(dg, sg, off), "2" = rbfdot(sg), "3" = tanhdot(sg * 0.3, off - 0.5),
               "5" = laplacedot(sg), "7" = anovadot(sg, dg), "8" = splinedot())
  gam <- switch(as.character(kt), "0" = 0, "1" = sg, "2" = sg, "3" = sg * 0.3, "5" = sg, "7" = sg, "8" = 0)
  cf <- switch(as.character(kt), "1" = off, "3" = off - 0.5, 0)
  dgr <- if (kt %in% c(1, 7)) dg else 1
  full <- numeric(n)
  if (sv <= 1) {
    n1 <- n %/% 2; x <- rbind(matrix(rnorm(n1 * p, -0.6, 0.8), n1), matrix(rnorm((n - n1) * p, 0.6, 0.8), n - n1))
    if (kt == 8) x <- x / 3
    yf <- factor(rep(1:2, c(n1, n - n1))); yd <- ifelse(as.integer(yf) == 1, -1, 1)
    m <- ksvm(x, yf, type = if (sv == 0) "C-svc" else "nu-svc", kernel = kn, C = C, nu = nu, scaled = FALSE)
    full[alphaindex(m)[[1]]] <- coef(m)[[1]]
  } else {
    x <- matrix(rnorm(n * p), n); if (kt == 8) x <- x / 3
    if (sv == 2) {
      yd <- rep(1, n); m <- ksvm(x, type = "one-svc", kernel = kn, nu = nu, scaled = FALSE)
    } else {
      yd <- sin(x[, 1]) + 0.1 * rnorm(n)
      m <- ksvm(x, yd, type = if (sv == 3) "eps-svr" else "nu-svr", kernel = kn, C = C, nu = nu, epsilon = pe, scaled = FALSE)
    }
    full[alphaindex(m)] <- coef(m)
  }
  K <- as.matrix(kernelMatrix(kn, x)); dec <- as.vector(K %*% full - b(m))
  a <- c(n, p, kt, sv, C, nu, pe, gam, dgr, cf, yd, as.vector(t(x)))
  add("alpha", a, ws(full)); add("rho", a, b(m)); add("obj", a, obj(m)); add("dec", a, ws(dec))
}
# Bessel kernel (ktype 6): besseldot(sigma, order, degree) carried as gamma = sigma, degree = order, coef0 = kernlab's degree
for (rep in 1:20) {
  kt <- 6; sv <- (rep - 1) %% 5
  n <- sample(20:40, 1); p <- sample(2:4, 1)
  C <- runif(1, 0.5, 8); nu <- runif(1, 0.1, 0.5); pe <- runif(1, 0.05, 0.3)
  sg <- runif(1, 0.2, 1.0); ord <- sample(1:3, 1); dg <- sample(1:3, 1)
  kn <- besseldot(sg, ord, dg)
  full <- numeric(n)
  if (sv <= 1) {
    n1 <- n %/% 2; x <- rbind(matrix(rnorm(n1 * p, -0.6, 0.8), n1), matrix(rnorm((n - n1) * p, 0.6, 0.8), n - n1))
    yf <- factor(rep(1:2, c(n1, n - n1))); yd <- ifelse(as.integer(yf) == 1, -1, 1)
    m <- ksvm(x, yf, type = if (sv == 0) "C-svc" else "nu-svc", kernel = kn, C = C, nu = nu, scaled = FALSE)
    full[alphaindex(m)[[1]]] <- coef(m)[[1]]
  } else {
    x <- matrix(rnorm(n * p), n)
    if (sv == 2) {
      yd <- rep(1, n); m <- ksvm(x, type = "one-svc", kernel = kn, nu = nu, scaled = FALSE)
    } else {
      yd <- sin(x[, 1]) + 0.1 * rnorm(n)
      m <- ksvm(x, yd, type = if (sv == 3) "eps-svr" else "nu-svr", kernel = kn, C = C, nu = nu, epsilon = pe, scaled = FALSE)
    }
    full[alphaindex(m)] <- coef(m)
  }
  K <- as.matrix(kernelMatrix(kn, x)); dec <- as.vector(K %*% full - b(m))
  a <- c(n, p, kt, sv, C, nu, pe, sg, ord, dg, yd, as.vector(t(x)))
  add("alpha", a, ws(full)); add("rho", a, b(m)); add("obj", a, obj(m)); add("dec", a, ws(dec))
}
emit("kernlabsvm", "kernlab", list(cases))
