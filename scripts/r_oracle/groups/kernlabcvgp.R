# kernlab gausspr(cross = k): classification (error rate) and regression (scaled = TRUE, squared error), rbfdot kernel, on R's stream.
#   args: (n, p, K, sigma, var, cross, scaled, seed, lab[n], x[n*p] row-major); K = 0 for regression (lab the target); fn "cross"
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261901)
for (rep in 1:30) {
  reg <- rep %% 3 == 0; p <- sample(2:4, 1); sg <- runif(1, 0.1, 1.0); vr <- runif(1, 0.2, 2); cr <- sample(3:6, 1)
  sd0 <- sample(100000, 1)
  if (!reg) {
    K <- c(2, 3, 4)[rep %% 3 + 1]; per <- sample(8:14, 1); n <- K * per; sc <- rep %% 2 == 0
    ctr <- matrix(rnorm(K * p, 0, 1.2), K); lab <- rep(1:K, per)[sample(n)]
    x <- ctr[lab, , drop = FALSE] + matrix(rnorm(n * p), n)
    set.seed(sd0)
    m <- gausspr(x, factor(lab), kernel = "rbfdot", kpar = list(sigma = sg), var = vr, scaled = sc, cross = cr)
  } else {
    K <- 0; n <- sample(25:45, 1); sc <- TRUE; x <- matrix(rnorm(n * p), n); lab <- 2 + 3 * sin(x[, 1]) + 0.3 * rnorm(n)
    set.seed(sd0)
    m <- gausspr(x, lab, kernel = "rbfdot", kpar = list(sigma = sg), var = vr, scaled = sc, cross = cr)
  }
  add("cross", c(n, p, K, sg, vr, cr, sc, sd0, lab, as.vector(t(x))), cross(m))
}
emit("kernlabcvgp", "kernlab", list(cases))
