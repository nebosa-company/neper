# MASS sammon, isoMDS and Shepard. The start configuration (cmdscale) is passed as an argument.
# Tolerance 1e-4 for p != 2: pow() differs from R by an ulp (mass_probe.R kind 2), which moves the vmmin stopping iteration; p = 2 and sammon are 1e-8
#   "sammon" (n, k, niter, magic, tol, mode, D[n n] col-major, Y[n k] col-major)  mode 0 stress, 1 position-weighted sum of the points
#   "isomds" (n, k, p, maxit, tol, mode, D, Y)                                   mode 0 stress, 1 weighted sum of the points
#   "shepard" (n, k, p, mode, d[nd], X[n k] col-major)                            mode 1 weighted sum of yf, 2 weighted sum of y
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20262400)
for (rep in 1:24) {
  n <- sample(6:22, 1); k <- if (rep %% 4 == 0) 3 else 2; pdim <- sample(3:6, 1)
  X <- matrix(rnorm(n * pdim), n, pdim) %*% diag(runif(pdim, 0.5, 3), pdim)
  D <- dist(X); Dm <- as.matrix(D); Y <- cmdscale(D, k)
  niter <- c(5, 20, 100)[rep %% 3 + 1]; magic <- c(0.2, 0.1, 0.4)[rep %% 3 + 1]; tol <- c(1e-4, 1e-3)[rep %% 2 + 1]
  s <- tryCatch(sammon(D, Y, k = k, niter = niter, magic = magic, tol = tol, trace = FALSE), error = function(e) NULL)
  if (!is.null(s)) {
    a <- c(n, k, niter, magic, tol)
    add("sammon", c(a, 0, as.vector(Dm), as.vector(Y)), s$stress)
    add("sammon", c(a, 1, as.vector(Dm), as.vector(Y)), sum(seq_along(s$points) * as.vector(s$points)))
  }
  p <- c(2, 2, 1.5, 3)[rep %% 4 + 1]; maxit <- c(50, 10, 100)[rep %% 3 + 1]; tl <- c(1e-3, 1e-5)[rep %% 2 + 1]
  Dp <- if (p == 2) D else dist(X, "minkowski", p = p)
  Yp <- cmdscale(Dp, k); Dpm <- as.matrix(Dp)
  r <- tryCatch(isoMDS(Dp, Yp, k = k, maxit = maxit, tol = tl, trace = FALSE, p = p), error = function(e) NULL)
  if (!is.null(r)) {
    a <- c(n, k, p, maxit, tl)
    # p != 2 goes through pow(), whose last-bit differences from R's libm move vmmin's stopping iteration: 1e-4 relative there
    rr <- if (p == 2) 1e-8 else 1e-4; aa <- if (p == 2) 1e-9 else 1e-3
    add("isomds", c(a, 0, as.vector(Dpm), as.vector(Yp)), r$stress, rel = rr, abs = aa)
    add("isomds", c(a, 1, as.vector(Dpm), as.vector(Yp)), sum(seq_along(r$points) * as.vector(r$points)), rel = rr, abs = aa)
    sh <- Shepard(Dp, r$points, p = p)
    a <- c(n, k, p)
    add("shepard", c(a, 1, as.vector(Dp), as.vector(r$points)), sum(seq_along(sh$yf) * sh$yf), rel = 1e-8)
    add("shepard", c(a, 2, as.vector(Dp), as.vector(r$points)), sum(seq_along(sh$y) * sh$y), rel = 1e-8)
  }
}

# a start that is not cmdscale (random), and NA / Inf distances (the start must then be given; isoMDS ranks the missing pairs last)
for (rep in 1:24) {
  n <- sample(7:20, 1); k <- if (rep %% 4 == 0) 3 else 2; pdim <- sample(3:5, 1)
  X <- matrix(rnorm(n * pdim), n, pdim); D <- dist(X); Dm <- as.matrix(D); Y0 <- matrix(rnorm(n * k), n, k)
  if (rep %% 2 == 1) {
    ij <- which(lower.tri(Dm)); miss <- sample(ij, max(1, length(ij) %/% 12)); Dm[miss] <- if (rep %% 6 == 5) Inf else NA
    Dm[t(Dm) %in% c(NA, Inf) & upper.tri(Dm)] <- NA
    Dm[upper.tri(Dm)] <- t(Dm)[upper.tri(Dm)]
    if (any(rowSums(is.na(Dm) & !diag(n)) > n - 3)) next
    Yst <- cmdscale(as.dist(replace(Dm, !is.finite(Dm), mean(Dm[is.finite(Dm)]))), k)
  } else Yst <- Y0
  niter <- c(10, 40, 100)[rep %% 3 + 1]; maxit <- c(30, 60, 100)[rep %% 3 + 1]
  if (!any(is.infinite(Dm))) {
    s <- tryCatch(sammon(as.dist(Dm), Yst, k = k, niter = niter, trace = FALSE), error = function(e) NULL)
    if (!is.null(s)) { a <- c(n, k, niter, 0.2, 1e-4); add("sammon", c(a, 0, as.vector(Dm), as.vector(Yst)), s$stress); add("sammon", c(a, 1, as.vector(Dm), as.vector(Yst)), sum(seq_along(s$points) * as.vector(s$points))) }
  }
  r <- tryCatch(isoMDS(Dm, Yst, k = k, maxit = maxit, tol = 1e-3, trace = FALSE), error = function(e) NULL)
  if (!is.null(r)) { a <- c(n, k, 2, maxit, 1e-3); add("isomds", c(a, 0, as.vector(Dm), as.vector(Yst)), r$stress, rel = 1e-8, abs = 1e-9); add("isomds", c(a, 1, as.vector(Dm), as.vector(Yst)), sum(seq_along(r$points) * as.vector(r$points)), rel = 1e-8, abs = 1e-9) }
}
emit("mass_mds", "MASS", list(cases))
