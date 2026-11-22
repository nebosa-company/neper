# copula: bivariate copulas. Archimedean (family 0 clayton 1 frank 2 gumbel 3 amh 4 joe) density, distribution, Kendall tau;
# normal and t density, distribution, tau, rho, tail dependence; frank rho; pobs; empirical copula; fitCopula itau and irho;
# rCopula under set.seed for normal, t, clayton, frank and amh.
#   fn "d" "p" "tau" "rho_frank" "lam" args (family, theta, u, v)
#   fn "dn" "pn" args (rho, nu(0), u, v); "dt" "pt" args (rho, nu, u, v)
#   fn "taun" "rhon" "itaun" "irhon" "itauc" "itaug" args (x); "lamt" args (rho, nu)
#   fn "pobs" args (idx, x...); "emp" args (a, b, n, x(n), y(n)); "fit" args (kind, n, x(n), y(n))
#   fn "rcop" args (kind, seed, n, par, nu, row, col)
suppressMessages(library(copula))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261230)
mk <- function(fam, th) switch(fam + 1, claytonCopula(th), frankCopula(th), gumbelCopula(th), amhCopula(th), joeCopula(th))
for (rep in 1:100) {
  fam <- (rep - 1) %% 5
  th <- switch(fam + 1, runif(1, 0.1, 6), runif(1, 0.3, 10) * sample(c(-1, 1), 1), 1 + runif(1, 0.1, 5), runif(1, -0.95, 0.95), 1 + runif(1, 0.1, 5))
  cop <- mk(fam, th)
  u <- runif(1, 0.02, 0.98); v <- runif(1, 0.02, 0.98); a <- c(fam, th, u, v)
  add("d", a, dCopula(c(u, v), cop)); add("p", a, pCopula(c(u, v), cop))
  if (fam != 3 || abs(th) > 0.01) add("tau", a, tau(cop))
  if (fam == 1) add("rho_frank", a, rho(cop))
  lm <- lambda(cop); add("lam", c(fam, th, 0), lm[["lower"]]); add("lam", c(fam, th, 1), lm[["upper"]])
}
for (th in c(2, 2 + 1e-6, 2 - 2e-5, 1.3, 25)) add("tau", c(4, th, 0.5, 0.5), tau(joeCopula(th)))
for (th in c(1e-9, 0.5, -3, 30, -30, 700, 1e5, -1e5, 1e10, 1e100, -1e100, 1e154, -1e154, 1.5, 2.13, 4.2)) { add("tau", c(1, th, 0.5, 0.5), tau(frankCopula(th))); add("rho_frank", c(1, th, 0.5, 0.5), rho(frankCopula(th))) }
for (rep in 1:40) {
  r <- runif(1, -0.95, 0.95); nu <- sample(c(2, 3, 4, 7, 12), 1)
  u <- runif(1, 0.02, 0.98); v <- runif(1, 0.02, 0.98)
  add("dn", c(r, 0, u, v), dCopula(c(u, v), normalCopula(r))); add("pn", c(r, 0, u, v), pCopula(c(u, v), normalCopula(r)))
  add("dt", c(r, nu, u, v), dCopula(c(u, v), tCopula(r, df = nu)), rel = 1e-13, abs = 1e-15); add("pt", c(r, nu, u, v), pCopula(c(u, v), tCopula(r, df = nu)))
  add("taun", r, tau(normalCopula(r))); add("rhon", r, rho(normalCopula(r)))
  add("lamt", c(r, nu), lambda(tCopula(r, df = nu))[["lower"]])
  tt <- runif(1, -0.9, 0.9)
  add("itaun", tt, iTau(normalCopula(), tt)); add("irhon", tt, iRho(normalCopula(), tt))
  add("itauc", abs(tt), iTau(claytonCopula(), abs(tt))); add("itaug", abs(tt), iTau(gumbelCopula(), abs(tt)))
}
set.seed(77)
x <- c(3, 1, 4, 1, 5, 9, 2, 6, 5, 3)
for (i in 1:10) add("pobs", c(i, x), pobs(x)[i])
for (rep in 1:12) {
  n <- sample(20:40, 1)
  z <- rnorm(n); X <- cbind(z, 0.6 * z + 0.8 * rnorm(n)); U <- pobs(X)
  a <- runif(1); b <- runif(1)
  add("emp", c(a, b, n, X[, 1], X[, 2]), C.n(cbind(a, b), U))
  add("fit", c(0, n, X[, 1], X[, 2]), fitCopula(normalCopula(), U, method = "itau")@estimate)
  add("fit", c(1, n, X[, 1], X[, 2]), fitCopula(normalCopula(), U, method = "irho")@estimate)
  add("fit", c(2, n, X[, 1], X[, 2]), fitCopula(claytonCopula(), U, method = "itau")@estimate)
  add("fit", c(3, n, X[, 1], X[, 2]), fitCopula(gumbelCopula(), U, method = "itau")@estimate)
  add("fit", c(10, n, X[, 1], X[, 2]), fitCopula(tCopula(df = 5, df.fixed = TRUE), U, method = "itau")@estimate)
  add("fit", c(8, n, X[, 1], X[, 2]), fitCopula(claytonCopula(), U, method = "irho")@estimate)
  add("fit", c(9, n, X[, 1], X[, 2]), suppressWarnings(fitCopula(gumbelCopula(), U, method = "irho")@estimate))
  rg <- runif(1, -0.9, 0.97); add("irhoc", rg, iRho(claytonCopula(), rg))
  rg <- runif(1, -0.2, 0.97); add("irhog", rg, suppressWarnings(iRho(gumbelCopula(), rg)))
  add("fitml", c(1, n, X[, 1], X[, 2], 1), fitCopula(gumbelCopula(), U, method = "ml")@estimate, rel = 1e-7, abs = 1e-9)  # optim factr 1e7 stops within ~2e-9 of the optimum, so the last iterate is rounding-sensitive
}
# fitCopula ml on pobs and mpl on raw data (kind 0 clayton 1 gumbel 2 normal 3 frank 4 joe 5 amh 6 t), all against R's optim L-BFGS-B
mkc <- function(kind) switch(kind + 1, claytonCopula(), gumbelCopula(), normalCopula(), frankCopula(), joeCopula(), amhCopula(), tCopula())
gen <- function(kind, n) {
  cop <- switch(kind + 1, claytonCopula(runif(1, 0.5, 4)), gumbelCopula(runif(1, 1.3, 4)), normalCopula(runif(1, -0.7, 0.8)),
                frankCopula(runif(1, 1, 8) * sample(c(-1, 1), 1)), joeCopula(runif(1, 1.3, 4)), amhCopula(runif(1, -0.6, 0.9)),
                tCopula(runif(1, 0.2, 0.8), df = sample(c(3, 5, 8), 1)))
  rCopula(n, cop)
}
for (rep in 1:5) for (kind in c(0, 2, 3, 4, 5, 6)) {
  n <- sample(30:60, 1)
  X <- gen(kind, n); U <- pobs(X)
  est <- tryCatch(fitCopula(mkc(kind), U, method = "ml")@estimate, error = function(e) NULL)
  if (is.null(est) || anyNA(est) || (kind == 6 && est[2] > 100)) next  # df > 100: flat likelihood, optim stops anywhere along it
  for (ix in seq_along(est)) add("fitml", c(kind, n, X[, 1], X[, 2], ix), est[ix], rel = if (kind == 0) 1e-5 else 1e-7, abs = 1e-9)  # Clayton: optim stops within its factr 1e7 tolerance (4e-6 seen)
  X2 <- cbind(qexp(X[, 1]), qnorm(X[, 2]))
  est <- tryCatch(fitCopula(mkc(kind), pobs(X2), method = "mpl")@estimate, error = function(e) NULL)
  if (is.null(est) || anyNA(est) || (kind == 6 && est[2] > 100)) next  # df > 100: flat likelihood, optim stops anywhere along it
  for (ix in seq_along(est)) add("fitml", c(kind, n, X2[, 1], X2[, 2], ix), est[ix], rel = if (kind == 0) 1e-5 else 1e-7, abs = 1e-9)  # Clayton: optim stops within its factr 1e7 tolerance (4e-6 seen)
}
for (rep in 1:5) {
  n <- sample(30:60, 1); X <- gen(3, n); U <- pobs(X)
  add("fit", c(4, n, X[, 1], X[, 2]), fitCopula(frankCopula(), U, method = "itau")@estimate)
  add("fit", c(7, n, X[, 1], X[, 2]), fitCopula(frankCopula(), U, method = "irho")@estimate, rel = 1e-7)  # uniroot tol 1e-7 fixes the last iterate only to the tolerance
  X <- gen(4, n); U <- pobs(X)
  add("fit", c(5, n, X[, 1], X[, 2]), fitCopula(joeCopula(), U, method = "itau")@estimate)
  X <- gen(5, n); U <- pobs(X)
  add("fit", c(6, n, X[, 1], X[, 2]), fitCopula(amhCopula(), U, method = "itau")@estimate)
}
# gofCopula(method = "Sn", estim.method = "mpl", simulation = "pb") under set.seed: statistic, bootstrap p-value and estimate
#   fn "gof" args (kind, seed, n, N, which, x(n), y(n)); which 1 statistic, 2 p.value, 3 estimate
for (kind in c(0, 1, 2, 3, 4, 5)) for (rep in 1:2) {
  n <- 40; seed <- 1000 + 10 * kind + rep
  X <- gen(kind, n)
  g <- tryCatch({ set.seed(seed); gofCopula(mkc(kind), X, N = 8, method = "Sn", estim.method = "mpl", simulation = "pb", verbose = FALSE) }, error = function(e) NULL)
  if (is.null(g)) next
  want <- c(g$statistic, g$p.value, g$parameter)
  for (w in 1:3) add("gof", c(kind, seed, n, 8, w, X[, 1], X[, 2]), want[w], rel = if (w == 2) 1e-12 else 1e-6, abs = 1e-12)
}
# mvdc (marginal distribution copulas), margins 0 norm(mean, sd) 1 exp(rate) 2 gamma(shape, rate) 3 lnorm(meanlog, sdlog); copula kinds as above, 6 = t with df nu fixed
#   fn "mv_d" args (ck, th, nu, mk0, mk1, p0(2), p1(2), x, y, log); "mv_p" args (ck, th, nu, mk0, mk1, p0(2), p1(2), x, y)
#   fn "mv_r" args (ck, th, nu, mk0, mk1, p0(2), p1(2), seed, n, row, col); "mv_fit" args (ck, nu, mk0, mk1, n, which, start(np0+np1+1), x(n), y(n))
mvnm <- c("norm", "exp", "gamma", "lnorm")
mvpar <- function(k, p) switch(k + 1, list(mean = p[1], sd = p[2]), list(rate = p[1]), list(shape = p[1], rate = p[2]), list(meanlog = p[1], sdlog = p[2]))
mvnp <- function(k) if (k == 1) 1 else 2
mkmv <- function(ck, th, nu, mk0, mk1, p0, p1) {
  cop <- switch(ck + 1, claytonCopula(th), gumbelCopula(th), normalCopula(th), frankCopula(th), joeCopula(th), amhCopula(th), tCopula(th, df = nu, df.fixed = TRUE))
  mvdc(cop, c(mvnm[mk0 + 1], mvnm[mk1 + 1]), list(mvpar(mk0, p0), mvpar(mk1, p1)))
}
mvrandp <- function(k) switch(k + 1, c(runif(1, -1, 1), runif(1, 0.5, 2)), c(runif(1, 0.5, 3), 0), c(runif(1, 1.5, 4), runif(1, 0.5, 2)), c(runif(1, -0.5, 0.5), runif(1, 0.3, 1)))
mvth <- function(ck) switch(ck + 1, runif(1, 0.5, 4), runif(1, 1.3, 4), runif(1, -0.6, 0.8), runif(1, 1, 7) * sample(c(-1, 1), 1), runif(1, 1.3, 4), runif(1, -0.6, 0.9), runif(1, 0.2, 0.8))
mvcombos <- list(c(0, 0, 2), c(1, 1, 0), c(2, 0, 0), c(3, 2, 3), c(4, 0, 1), c(5, 3, 0), c(6, 0, 2), c(0, 3, 2), c(3, 0, 0), c(1, 2, 2))
for (cb in mvcombos) for (rep in 1:3) {
  ck <- cb[1]; mk0 <- cb[2]; mk1 <- cb[3]
  th <- mvth(ck); nu <- if (ck == 6) sample(c(3, 5, 8), 1) else 4
  p0 <- mvrandp(mk0); p1 <- mvrandp(mk1)
  mv <- mkmv(ck, th, nu, mk0, mk1, p0, p1)
  pre <- c(ck, th, nu, mk0, mk1, p0, p1)
  set.seed(500 + rep); xy <- rMvdc(3, mv)
  for (i in 1:3) {
    add("mv_d", c(pre, xy[i, ], 1), dMvdc(xy[i, ], mv, log = TRUE), rel = 1e-9, abs = 1e-12)
    add("mv_d", c(pre, xy[i, ], 0), dMvdc(xy[i, ], mv), rel = 1e-9, abs = 1e-12)
    add("mv_p", c(pre, xy[i, ]), pMvdc(xy[i, ], mv), rel = 1e-9, abs = 1e-12)
  }
  seed <- 600 + rep; set.seed(seed); m <- rMvdc(4, mv)
  for (i in 1:4) for (j in 1:2) add("mv_r", c(pre, seed, 4, i, j), m[i, j], rel = 1e-9, abs = 1e-12)
}
for (cb in mvcombos) for (rep in 1:2) {
  ck <- cb[1]; mk0 <- cb[2]; mk1 <- cb[3]
  th <- mvth(ck); nu <- if (ck == 6) sample(c(3, 5, 8), 1) else 4
  p0 <- mvrandp(mk0); p1 <- mvrandp(mk1)
  mv <- mkmv(ck, th, nu, mk0, mk1, p0, p1)
  n <- 60; set.seed(700 + rep); X <- rMvdc(n, mv)
  tr <- c(p0[seq_len(mvnp(mk0))], p1[seq_len(mvnp(mk1))], th)
  start <- round(tr * 1.1 + 0.05, 3)
  fit <- tryCatch(suppressWarnings(fitMvdc(X, mv, start = start, estimate.variance = FALSE)), error = function(e) NULL)
  if (is.null(fit) || fit@fitting.stats$convergence != 0) next
  est <- fit@estimate
  for (w in seq_along(est)) add("mv_fit", c(ck, nu, mk0, mk1, n, w, start, X[, 1], X[, 2]), est[w], rel = 1e-8, abs = 1e-9)
}
# dimension d = 3, 4 (exchangeable): normal, t and Clayton log densities, Archimedean distribution functions, samplers
#   fn "hd_d" args (kind, th, nu, d, u(d)) kind 0 clayton 2 normal 6 t; "hd_p" args (fam, th, d, u(d)) fam as in "p";
#   fn "hd_r" args (kind, th, nu, d, seed, n, row, col) kind 0 clayton 1 gumbel 2 normal 3 frank 4 joe 6 t
hdcop <- function(kind, th, nu, d) switch(kind + 1, claytonCopula(th, dim = d), gumbelCopula(th, dim = d), normalCopula(th, dim = d), frankCopula(th, dim = d),
                                          joeCopula(th, dim = d), amhCopula(th, dim = d), tCopula(th, dim = d, df = nu, df.fixed = TRUE))
for (d in 3:4) for (rep in 1:5) {
  u <- runif(d, 0.05, 0.95)
  th <- runif(1, 0.3, 5); nu <- sample(c(3, 4.5, 8), 1)
  add("hd_d", c(0, th, nu, d, u), dCopula(u, claytonCopula(th, dim = d), log = TRUE))
  r <- runif(1, 0.1, 0.8)
  add("hd_d", c(2, r, nu, d, u), dCopula(u, normalCopula(r, dim = d), log = TRUE))
  add("hd_d", c(6, r, nu, d, u), dCopula(u, tCopula(r, dim = d, df = nu, df.fixed = TRUE), log = TRUE))
  for (fam in c(0, 1, 2, 4)) {
    thf <- switch(fam + 1, th, th, 1 + th, runif(1, 0.1, 0.9), 1 + th)
    add("hd_p", c(fam, thf, d, u), pCopula(u, switch(fam + 1, claytonCopula(thf, dim = d), frankCopula(thf, dim = d), gumbelCopula(thf, dim = d), amhCopula(thf, dim = d), joeCopula(thf, dim = d))), rel = 1e-9)
  }
}
hdr <- function(kind, th, nu, d, seed, n = 5) {
  set.seed(seed)
  m <- rCopula(n, hdcop(kind, th, nu, d))
  for (i in 1:n) for (j in 1:d) add("hd_r", c(kind, th, nu, d, seed, n, i, j), m[i, j])
}
for (d in 3:4) {
  hdr(0, 1.7, 0, d, 31 + d); hdr(1, 2.4, 0, d, 41 + d); hdr(2, 0.55, 0, d, 51 + d); hdr(3, 3.1, 0, d, 61 + d)
  hdr(4, 2.2, 0, d, 71 + d); hdr(6, 0.45, 5, d, 81 + d); hdr(3, 12, 0, d, 91 + d); hdr(1, 6, 0, d, 101 + d)
}
rc <- function(kind, par, nu, seed, n = 6) {
  set.seed(seed)
  cop <- switch(kind + 1, normalCopula(par), tCopula(par, df = nu), claytonCopula(par), frankCopula(par), amhCopula(par), gumbelCopula(par), joeCopula(par))
  m <- rCopula(n, cop)
  for (i in 1:n) for (j in 1:2) add("rcop", c(kind, seed, n, par, nu, i, j), m[i, j])
}
rc(0, 0.7, 0, 11); rc(0, -0.4, 0, 12); rc(1, 0.5, 4, 13); rc(1, -0.3, 7, 14)
rc(2, 2.5, 0, 15); rc(3, 4, 0, 16); rc(3, -5, 0, 17); rc(4, 0.6, 0, 18); rc(4, -0.7, 0, 19)
rc(5, 1.5, 0, 21); rc(5, 3.2, 0, 22); rc(5, 8, 0, 23, 10); rc(6, 1.4, 0, 24); rc(6, 2.7, 0, 25); rc(6, 7, 0, 26, 10)
emit("copula", "copula", list(cases))
