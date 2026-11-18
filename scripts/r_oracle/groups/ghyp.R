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
# ghypMom: args (order, kind 0 raw / 1 central / 2 mu, mu, delta, alpha, beta, lambda) under "ghypMom"; ghypSkew under "ghypSkew"
for (rep in 1:15) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 3)
  for (ord in 1:5) for (kd in 0:2) {
    mt <- c("raw", "central", "mu")[kd + 1]
    v <- tryCatch(ghypMom(ord, param = c(mu, delta, alpha, beta, lam), momType = mt), error = function(e) NA_real_)
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("ghypMom", c(ord, kd, mu, delta, alpha, beta, lam), v, rel = 1e-7, abs = 1e-10)
  }
  cases[[length(cases) + 1]] <- case("ghypSkew", c(0, 0, mu, delta, alpha, beta, lam), ghypSkew(param = c(mu, delta, alpha, beta, lam)), rel = 1e-6, abs = 1e-9)
}
# ghypKurt (order slot 0) and pgig (x, chi, psi, lambda) under "pgig", checked at 1e-7
for (rep in 1:15) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 3)
  cases[[length(cases) + 1]] <- case("ghypKurt", c(0, 0, mu, delta, alpha, beta, lam), ghypKurt(param = c(mu, delta, alpha, beta, lam)), rel = 1e-6, abs = 1e-9)
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3); lg <- runif(1, -2, 2)
  for (x in c(0.3, 1, 2.5)) cases[[length(cases) + 1]] <- case("pgig", c(x, chi, psi, lg, 0, 0, 0), pgig(x, chi, psi, lg), rel = 1e-7, abs = 1e-10)
}
# nigFit with a user start and Nelder-Mead: args (n, what, mu0, delta0, alpha0, beta0, 0, data...) under "nigFit"; what 0..3 the fitted mu, delta, alpha, beta, 4 the maximised
# log-likelihood, 5 the function count
for (rep in 1:5) {
  n <- sample(150:300, 1); mu <- rnorm(1); delta <- runif(1, 0.5, 2); alpha <- runif(1, 1, 3); beta <- runif(1, -0.6, 0.6) * alpha
  x <- rnig(n, mu, delta, alpha, beta)
  st <- c(mean(x), sd(x), 1.5, 0.1)
  fit <- tryCatch(nigFit(x, paramStart = st, startValues = "US", method = "Nelder-Mead"), error = function(e) NULL)
  if (is.null(fit)) next
  for (w in 0:3) cases[[length(cases) + 1]] <- case("nigFit", c(n, w, st, 0, x), as.numeric(fit$param[w + 1]), rel = 1e-5, abs = 1e-7)
  cases[[length(cases) + 1]] <- case("nigFit", c(n, 4, st, 0, x), as.numeric(fit$maxLik), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("nigFit", c(n, 5, st, 0, x), as.numeric(fit$iter), rel = 0, abs = 0)
}
# hyperbFit with a user start and Nelder-Mead, laid out as nigFit under "hyperbFit"
for (rep in 1:5) {
  n <- sample(150:300, 1); mu <- rnorm(1); delta <- runif(1, 0.5, 2); alpha <- runif(1, 1, 3); beta <- runif(1, -0.6, 0.6) * alpha
  x <- rhyperb(n, param = c(mu, delta, alpha, beta))
  st <- c(mean(x), sd(x), 1.5, 0.1)
  fit <- tryCatch(hyperbFit(x, paramStart = st, startValues = "US", method = "Nelder-Mead"), error = function(e) NULL)
  if (is.null(fit)) next
  for (w in 0:3) cases[[length(cases) + 1]] <- case("hyperbFit", c(n, w, st, 0, x), as.numeric(fit$param[w + 1]), rel = 1e-5, abs = 1e-7)
  cases[[length(cases) + 1]] <- case("hyperbFit", c(n, 4, st, 0, x), as.numeric(fit$maxLik), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("hyperbFit", c(n, 5, st, 0, x), as.numeric(fit$iter), rel = 0, abs = 0)
}
# "ddghyp" (x, mu, delta, alpha, beta, lambda); "chpars" (from, to, delta, p3, p4, index) over the five parametrizations
for (rep in 1:30) {
  mu <- round(rnorm(1), 2); delta <- runif(1, 0.5, 2); alpha <- runif(1, 1.2, 3); beta <- runif(1, -0.9, 0.9); lam <- sample(c(-1.5, -0.5, 0.5, 1, 2), 1); x <- rnorm(1, mu, 1.5)
  add("ddghyp", c(x, mu, delta, alpha, beta, lam), ddghyp(x, param = c(mu, delta, alpha, beta, lam)))
}
for (from in 1:5) for (to in 1:5) for (rep in 1:4) {
  delta <- runif(1, 0.5, 2); alpha <- runif(1, 1.2, 3); beta <- runif(1, -0.9, 0.9); pr <- c(0, delta, alpha, beta, 1)
  q <- if (from == 1) pr else ghypChangePars(1, from, pr)
  r <- ghypChangePars(from, to, q)
  for (j in 1:2) add("chpars", c(from, to, delta, q[3], q[4], j - 1), r[2 + j])
}
emit("ghyp", "GeneralizedHyperbolic", list(cases))
