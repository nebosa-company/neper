# kernlab ksvm(cross = k) for C-svc, nu-svc, C-bsvc (classification, error rate) and eps-svr, nu-svr (regression, squared error), rbfdot kernel, on R's stream.
#   args: (n, p, K, svm, C, nu, pe, sigma, cross, scaled, seed, lab[n], x[n*p] row-major); lab is the 1-based class for svm 0, 1, 5 and the target for svm 3, 4; fn "cross"
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261701)
svms <- c(0, 1, 5, 3, 4)
for (rep in 1:40) {
  sv <- svms[(rep - 1) %% 5 + 1]; K <- c(2, 3, 4)[(rep - 1) %/% 5 %% 3 + 1]; p <- sample(2:4, 1)
  C <- runif(1, 0.5, 8); nu <- runif(1, 0.1, 0.4); pe <- runif(1, 0.05, 0.3); sg <- runif(1, 0.1, 1.0)
  cr <- sample(3:6, 1); sc <- rep %% 2 == 0; sd0 <- sample(100000, 1)
  if (sv %in% c(0, 1, 5)) {
    per <- sample(8:14, 1); n <- K * per
    ctr <- matrix(rnorm(K * p, 0, 1.2), K); lab <- rep(1:K, per)[sample(n)]
    x <- ctr[lab, , drop = FALSE] + matrix(rnorm(n * p), n)
    set.seed(sd0)
    m <- ksvm(x, factor(lab), type = c("0" = "C-svc", "1" = "nu-svc", "5" = "C-bsvc")[as.character(sv)], kernel = rbfdot(sg), C = C, nu = nu, scaled = sc, cross = cr)
  } else {
    K <- 0; n <- sample(25:50, 1); x <- matrix(rnorm(n * p), n); lab <- 2 + 3 * sin(x[, 1]) + 0.3 * rnorm(n)
    set.seed(sd0)
    m <- ksvm(x, lab, type = if (sv == 3) "eps-svr" else "nu-svr", kernel = rbfdot(sg), C = C, nu = nu, epsilon = pe, scaled = sc, cross = cr)
  }
  add("cross", c(n, p, K, sv, C, nu, pe, sg, cr, sc, sd0, lab, as.vector(t(x))), cross(m))
}
emit("kernlabcv", "kernlab", list(cases))
