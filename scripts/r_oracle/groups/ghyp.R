# ghyp: GeneralizedHyperbolic densities.
#   pghyp ("pghyp": q, mu, delta, alpha, beta, lambda), pnig and phyperb (q, mu, delta, alpha, beta, 0) are the integrate-based distributions, checked at 1e-6.
#   args: "dghyp" (x, mu, delta, alpha, beta, lambda); "dnig" and "dhyperb" (x, mu, delta, alpha, beta, 0); "dskewlap" (x, mu, alpha, beta, 0, 0)
suppressMessages(library(GeneralizedHyperbolic))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-14)
set.seed(20262003)
for (rep in 1:30) {
  mu <- runif(1, -2, 2); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.5, 4); beta <- runif(1, -0.9, 0.9) * alpha; lam <- runif(1, -3, 3)
  for (x in mu + c(-3, -0.7, 0, 0.4, 2.5) * delta) {
    add("dghyp", c(x, mu, delta, alpha, beta, lam), dghyp(x, param = c(mu, delta, alpha, beta, lam)))
    add("dnig", c(x, mu, delta, alpha, beta, 0), dnig(x, mu, delta, alpha, beta))
    add("dhyperb", c(x, mu, delta, alpha, beta, 0), dhyperb(x, mu, delta, alpha, beta))
  }
  a <- runif(1, 0.3, 2); b <- runif(1, 0.3, 2)
  for (x in mu + c(-2, -0.1, 0.3, 1.5)) add("dskewlap", c(x, mu, a, b, 0, 0), dskewlap(x, mu, a, b))
}
for (rep in 1:20) {
  mu <- runif(1, -2, 2); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 2)
  for (x in mu + c(-3, -0.7, 0.4, 2.5) * delta) {
    cases[[length(cases) + 1]] <- case("pghyp", c(x, mu, delta, alpha, beta, lam), pghyp(x, param = c(mu, delta, alpha, beta, lam)), rel = 1e-6, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("pnig", c(x, mu, delta, alpha, beta, 0), pnig(x, mu, delta, alpha, beta), rel = 1e-6, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("phyperb", c(x, mu, delta, alpha, beta, 0), phyperb(x, mu, delta, alpha, beta), rel = 1e-6, abs = 1e-9)
  }
}
for (rep in 1:30) {
  mu <- runif(1, -2, 2); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 3)
  cases[[length(cases) + 1]] <- case("ghypMean", c(mu, delta, alpha, beta, lam, 0), ghypMean(param = c(mu, delta, alpha, beta, lam)), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("ghypVar", c(mu, delta, alpha, beta, lam, 0), ghypVar(param = c(mu, delta, alpha, beta, lam)), rel = 1e-9, abs = 1e-13)
}
for (rep in 1:5) {
  mu <- runif(1, -2, 2); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 2)
  for (pp in c(0.1, 0.5, 0.9)) {
    qv <- tryCatch(qghyp(pp, param = c(mu, delta, alpha, beta, lam)), error = function(e) NA_real_)
    if (is.finite(qv)) cases[[length(cases) + 1]] <- case("qghyp", c(pp, mu, delta, alpha, beta, lam), qv, rel = 1e-5, abs = 1e-7)
  }
}
# rghyp: (seed, n, i, mu, delta, alpha, beta, lambda) -> draw i of set.seed(seed); rghyp(n, param) (lambda != 1)
for (rep in 1:14) {
  mu <- runif(1, -2, 2); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- c(runif(1, -3, 0.9), runif(1, 1.1, 3), -0.5, 1)[sample(1:4, 1)]
  sd0 <- sample(1:100000, 1); n <- 6
  set.seed(sd0); v <- rghyp(n, param = c(mu, delta, alpha, beta, lam))
  for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("rghyp", c(sd0, n, i - 1, mu, delta, alpha, beta, lam), v[i], rel = 1e-9, abs = 1e-12)
}
# skew-Laplace p, q, r, and the GIG density and mean
for (rep in 1:20) {
  mu <- rnorm(1); al <- runif(1, 0.3, 2); be <- runif(1, 0.3, 2)
  for (x in mu + c(-2, -0.2, 0.3, 1.7)) cases[[length(cases) + 1]] <- case("pskewlap", c(x, mu, al, be, 0, 0), pskewlap(x, mu, al, be), rel = 1e-10, abs = 1e-14)
  for (pp in c(0.1, 0.5, 0.9)) cases[[length(cases) + 1]] <- case("qskewlap", c(pp, mu, al, be, 0, 0), qskewlap(pp, mu, al, be), rel = 1e-10, abs = 1e-12)
  sd0 <- sample(1:100000, 1); n <- 5; set.seed(sd0); v <- rskewlap(n, mu, al, be)
  for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("rskewlap", c(sd0, n, i - 1, mu, al, be), v[i], rel = 1e-10, abs = 1e-12)
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3); lam <- runif(1, -2, 2)
  for (x in c(0.2, 1, 3)) cases[[length(cases) + 1]] <- case("dgig", c(x, chi, psi, lam, 0, 0), dgig(x, chi, psi, lam), rel = 1e-8, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("gigMode", c(chi, psi, lam, 0, 0, 0), gigMode(chi, psi, lam), rel = 1e-10, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("gigVar", c(chi, psi, lam, 0, 0, 0), gigVar(chi, psi, lam), rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gigRaw3", c(chi, psi, lam, 0, 0, 0), gigRawMom(3, chi, psi, lam), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gigMean", c(chi, psi, lam, 0, 0, 0), gigMean(chi, psi, lam), rel = 1e-9, abs = 1e-13)
}
emit("ghyp", "GeneralizedHyperbolic", list(cases))
