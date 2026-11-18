# aod: varbin's non-bootstrap rows, iccbin method C and donner. drs args: (0 rho / 1 X2, 0, 0, k, n..., y..., group codes 0-based..., G) under the name "donner". wald.test: (0 chi2 / 1 P, q, p, b..., sigma row-major..., L row-major...) under the name "wald".
#   args: "varbin" (row 0 binomial, 1 ratio, 2 arithmetic, 3 jackknife; part 0 p, 1 varp, 2 lower, 3 upper; alpha; k; n...; y...); "iccbin" (0, 0, 0, k, n..., y...)
suppressMessages(library(aod))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-13)
set.seed(20262006)
for (rep in 1:25) {
  k <- sample(6:30, 1); n <- sample(3:25, k, TRUE); pr <- runif(k, 0.1, 0.7); y <- rbinom(k, n, pr)
  df <- data.frame(n = n, y = y)
  vb <- suppressWarnings(varbin(n, y, df, alpha = 0.1, R = 200))@tab
  for (r in 0:3) { add("varbin", c(r, 0, 0.1, k, n, y), vb[r + 1, 1]); add("varbin", c(r, 1, 0.1, k, n, y), vb[r + 1, 2]); add("varbin", c(r, 2, 0.1, k, n, y), vb[r + 1, 3]); add("varbin", c(r, 3, 0.1, k, n, y), vb[r + 1, 4]) }
  ic <- iccbin(n, y, df, method = "C")@rho; add("iccbin", c(0, 0, 0, k, n, y), ic)
}
for (rep in 1:20) {
  G <- sample(2:4, 1); k <- sample((2 * G + 2):(5 * G + 6), 1)
  grp <- c(0:(G - 1), sample(0:(G - 1), k - G, TRUE)); n <- sample(3:30, k, TRUE); y <- rbinom(k, n, runif(k, 0.15, 0.65))
  d <- data.frame(r = y / n, g = factor(grp), w = n)
  dr <- donner(r ~ g, weights = w, data = d)
  add("donner", c(0, 0, 0, k, n, y, grp, G), dr@rho); add("donner", c(1, 0, 0, k, n, y, grp, G), dr@X2)
}
for (rep in 1:25) {
  p <- sample(2:6, 1); q <- sample(1:min(p, 3), 1)
  b <- rnorm(p, 0, 2); A <- matrix(rnorm(p * p), p, p); S <- crossprod(A) / p + diag(p) * 0.3
  L <- matrix(rnorm(q * p), q, p)
  w <- wald.test(b = b, Sigma = S, L = L)$result$chi2
  add("wald", c(0, q, p, b, as.vector(t(S)), as.vector(t(L))), w[["chi2"]]); add("wald", c(1, q, p, b, as.vector(t(S)), as.vector(t(L))), w[["P"]])
}
# quasipois (mode 0 phi estimated / 1 phi given, n, p, phi, x column-major n by p, y, index): coefficient index, or phi at index p
for (rep in 1:20) {
  n <- sample(25:60, 1); xv <- round(rnorm(n), 3); z <- round(runif(n), 3); mu <- exp(0.6 + 0.4 * xv + 0.5 * z)
  y <- rnbinom(n, mu = mu, size = 4); d <- data.frame(y = y, xv = xv, z = z)
  X <- cbind(1, xv, z)
  for (mode in 0:1) {
    ph <- if (mode == 1) runif(1, 0.05, 0.6) else NA
    fit <- suppressWarnings(if (mode == 1) quasipois(y ~ xv + z, data = d, phi = ph) else quasipois(y ~ xv + z, data = d))
    cf <- coef(fit@fm); pv <- fit@phi
    for (j in 1:3) add("qpois", c(mode, n, 3, if (mode == 1) ph else 0, as.vector(X), y, j - 1), cf[[j]])
    add("qpois", c(mode, n, 3, if (mode == 1) ph else 0, as.vector(X), y, 3), pv)
  }
}
# quasibin, logit link (mode 0 phi estimated / 1 phi given, n, p, phi, x column-major, successes, sizes, index)
for (rep in 1:20) {
  n <- sample(12:40, 1); xv <- round(rnorm(n), 3); sz <- sample(5:30, n, TRUE)
  pr <- plogis(-0.3 + 0.7 * xv); pr2 <- rbeta(n, 3 * pr + 0.2, 3 * (1 - pr) + 0.2); sc <- rbinom(n, sz, pr2)
  d <- data.frame(sc = sc, fl = sz - sc, xv = xv); X <- cbind(1, xv)
  for (mode in 0:1) {
    ph <- if (mode == 1) runif(1, 0.02, 0.3) else NA
    fit <- suppressWarnings(if (mode == 1) quasibin(cbind(sc, fl) ~ xv, data = d, phi = ph) else quasibin(cbind(sc, fl) ~ xv, data = d))
    cf <- coef(fit@fm)
    for (j in 1:2) add("qbin", c(mode, n, 2, if (mode == 1) ph else 0, as.vector(X), sc, sz, j - 1), cf[[j]])
    add("qbin", c(mode, n, 2, if (mode == 1) ph else 0, as.vector(X), sc, sz, 2), fit@phi)
  }
}
# betabin, logit link, phi constant (n, p, x column-major, successes, sizes, index): coefficient index, phi at p, the log-likelihood at p + 1; 1e-6 as the simplex stops at 1.5e-8 of the function value
for (rep in 1:15) {
  n <- sample(15:40, 1); xv <- round(rnorm(n), 3); sz <- sample(6:30, n, TRUE)
  pr <- plogis(-0.3 + 0.7 * xv); pr2 <- rbeta(n, 3 * pr + 0.5, 3 * (1 - pr) + 0.5); sc <- rbinom(n, sz, pr2)
  d <- data.frame(sc = sc, fl = sz - sc, xv = xv); X <- cbind(1, xv)
  fit <- suppressWarnings(betabin(cbind(sc, fl) ~ xv, ~ 1, data = d))
  pa <- fit@param; ll <- fit@logL
  for (j in 1:3) cases[[length(cases) + 1]] <- case("bbin", c(n, 2, as.vector(X), sc, sz, j - 1), pa[[j]], rel = 1e-6, abs = 1e-8)
  cases[[length(cases) + 1]] <- case("bbin", c(n, 2, as.vector(X), sc, sz, 3), ll, rel = 1e-6, abs = 1e-8)
  sev <- sqrt(diag(fit@varparam))
  for (j in 1:3) cases[[length(cases) + 1]] <- case("bbin", c(n, 2, as.vector(X), sc, sz, 3 + j), sev[[j]], rel = 1e-4, abs = 1e-6)
}
# negbin, log link, phi constant (n, p, x column-major, counts, index): coefficient index, phi at p, the log-likelihood at p + 1; 1e-6 as for betabin
for (rep in 1:15) {
  n <- sample(20:50, 1); xv <- round(rnorm(n), 3); mu <- exp(1 + 0.4 * xv)
  y <- rnbinom(n, mu = mu, size = 3); d <- data.frame(y = y, xv = xv); X <- cbind(1, xv)
  fit <- suppressWarnings(negbin(y ~ xv, ~ 1, data = d))
  pa <- fit@param; ll <- fit@logL
  for (j in 1:3) cases[[length(cases) + 1]] <- case("nbin", c(n, 2, as.vector(X), y, j - 1), pa[[j]], rel = 1e-6, abs = 1e-8)
  cases[[length(cases) + 1]] <- case("nbin", c(n, 2, as.vector(X), y, 3), ll, rel = 1e-6, abs = 1e-8)
  sev <- sqrt(diag(fit@varparam))
  for (j in 1:3) cases[[length(cases) + 1]] <- case("nbin", c(n, 2, as.vector(X), y, 3 + j), sev[[j]], rel = 1e-4, abs = 1e-6)
}
# splitbin (k, n..., y..., index): the index-th response of the Bernoulli expansion, and the table length at index -1
for (rep in 1:10) {
  k <- sample(3:8, 1); nn <- sample(1:7, k, TRUE); yy <- rbinom(k, nn, 0.5); df <- data.frame(n = nn, y = yy)
  tb <- splitbin(cbind(y, n - y) ~ 1, df)$tab
  cases[[length(cases) + 1]] <- case("splitbin", c(k, nn, yy, -1), nrow(tb))
  for (r in seq_len(nrow(tb))) cases[[length(cases) + 1]] <- case("splitbin", c(k, nn, yy, r - 1), tb$y[r])
}
# betabin and negbin with phi by a two- or three-level group ("bbing", "nbing": n, p, ng, grp, ..., index into coefficients, phis, log-likelihood), and the anova of nested fits ("anova": ll1, k1, ll2, k2, j)
for (rep in 1:10) {
  n <- sample(30:60, 1); xv <- round(rnorm(n), 3); sz <- sample(8:30, n, TRUE); ng <- sample(2:3, 1); gr <- c(0:(ng - 1), sample(0:(ng - 1), n - ng, TRUE))
  pr <- plogis(-0.3 + 0.6 * xv); pr2 <- rbeta(n, 3 * pr + 0.5, 3 * (1 - pr) + 0.5); sc <- rbinom(n, sz, pr2)
  d <- data.frame(sc = sc, fl = sz - sc, xv = xv, g = factor(gr)); X <- cbind(1, xv)
  fit <- suppressWarnings(betabin(cbind(sc, fl) ~ xv, ~ g, data = d)); pa <- fit@param; ll <- fit@logL
  for (j in seq_along(pa)) cases[[length(cases) + 1]] <- case("bbing", c(n, 2, ng, gr, as.vector(X), sc, sz, j - 1), pa[[j]], rel = 1e-5, abs = 1e-7)
  cases[[length(cases) + 1]] <- case("bbing", c(n, 2, ng, gr, as.vector(X), sc, sz, length(pa)), ll, rel = 1e-6, abs = 1e-8)
  fit0 <- suppressWarnings(betabin(cbind(sc, fl) ~ xv, ~ 1, data = d))
  an <- suppressWarnings(anova(fit0, fit)); lrt <- 2 * (fit@logL - fit0@logL); dfd <- length(fit@param) - length(fit0@param)
  cases[[length(cases) + 1]] <- case("anova", c(fit0@logL, length(fit0@param), fit@logL, length(fit@param), 0), lrt, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("anova", c(fit0@logL, length(fit0@param), fit@logL, length(fit@param), 2), pchisq(lrt, dfd, lower.tail = FALSE), rel = 1e-9, abs = 1e-12)
  yc <- rnbinom(n, mu = exp(1 + 0.3 * xv), size = 3)
  dn <- data.frame(y = yc, xv = xv, g = factor(gr))
  fn_ <- suppressWarnings(negbin(y ~ xv, ~ g, data = dn)); pn <- fn_@param
  for (j in seq_along(pn)) cases[[length(cases) + 1]] <- case("nbing", c(n, 2, ng, gr, as.vector(X), yc, j - 1), pn[[j]], rel = 1e-5, abs = 1e-7)
  cases[[length(cases) + 1]] <- case("nbing", c(n, 2, ng, gr, as.vector(X), yc, length(pn)), fn_@logL, rel = 1e-6, abs = 1e-8)
}
# iccbin methods A and B (glmer nAGQ = 1): "icc2" args (method 0 A / 1 B, seed, M, k, n..., y...); 1e-3 as lme4's optimiser stops at 1e-5 on the deviance
for (rep in 1:12) {
  k <- sample(8:25, 1); n <- sample(6:25, k, TRUE); cl <- rbeta(k, 2, 3); y <- rbinom(k, n, cl); df <- data.frame(n = n, y = y)
  sd0 <- sample(1:100000, 1); M <- 1000
  ra <- tryCatch(suppressWarnings(suppressMessages(iccbin(n, y, df, method = "A")@rho)), error = function(e) NA)
  set.seed(sd0); rb <- tryCatch(suppressWarnings(suppressMessages(iccbin(n, y, df, method = "B", M = M)@rho)), error = function(e) NA)
  if (is.na(ra) || ra < 0.02) next
  cases[[length(cases) + 1]] <- case("icc2", c(0, sd0, M, k, n, y), ra, rel = 2e-3, abs = 1e-4)
  cases[[length(cases) + 1]] <- case("icc2", c(1, sd0, M, k, n, y), rb, rel = 2e-3, abs = 1e-4)
}
# the cloglog link: "bbcll" (betabin; n, p, x, sc, sz, index: coefficients, phi, log-likelihood), "qbcll" (quasibin, phi estimated; n, p, x, sc, sz, index: coefficients, phi)
for (rep in 1:12) {
  n <- sample(20:50, 1); xv <- round(rnorm(n), 3); sz <- sample(8:30, n, TRUE); X <- cbind(1, xv)
  pr <- 1 - exp(-exp(-0.8 + 0.5 * xv)); pr2 <- rbeta(n, 3 * pr + 0.5, 3 * (1 - pr) + 0.5); sc <- rbinom(n, sz, pr2)
  d <- data.frame(sc = sc, fl = sz - sc, xv = xv)
  fit <- suppressWarnings(betabin(cbind(sc, fl) ~ xv, ~ 1, data = d, link = "cloglog")); pa <- fit@param
  for (j in seq_along(pa)) cases[[length(cases) + 1]] <- case("bbcll", c(n, 2, as.vector(X), sc, sz, j - 1), pa[[j]], rel = 1e-5, abs = 1e-7)
  cases[[length(cases) + 1]] <- case("bbcll", c(n, 2, as.vector(X), sc, sz, length(pa)), fit@logL, rel = 1e-6, abs = 1e-8)
  qf <- suppressWarnings(quasibin(cbind(sc, fl) ~ xv, data = d, link = "cloglog")); cq <- coef(qf@fm)
  for (j in 1:2) cases[[length(cases) + 1]] <- case("qbcll", c(n, 2, as.vector(X), sc, sz, j - 1), cq[[j]], rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("qbcll", c(n, 2, as.vector(X), sc, sz, 2), qf@phi, rel = 1e-7, abs = 1e-9)
}
emit("aod", "aod", list(cases))
