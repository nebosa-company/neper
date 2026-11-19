# MASS cov.trob, lm.ridge, stdres / studres, contr.sdif and dose.p.
#   "trob"   (n, p, center 0 TRUE 1 FALSE 2 numeric, has.wt, nu, maxit, tol, mode 0 cov 1 center 2 iterations 3 n.obs, x[n p], wt[n] (if has.wt), ctr[p] (if numeric))
#   "ridge"  (n, p0, inter, k, mode 0 coef(fit) 1 GCV 2 kHKB 3 kLW 4 scales, lambda[k], x[n p0], y[n])
#   "stdres" (n, p0, inter, has.w, mode 0 stdres 1 studres 2 stddev, x[n p0], y[n], w[n] (if has.w))
#   "sdif"   (n, mode 0): the position-weighted sum of contr.sdif(n)
#   "dose"   (link 0 logit 1 probit 2 cloglog 3 cauchit 4 log, p, b1, b2, v11, v12, v22, mode 0 dose 1 SE)
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
quiet <- function(expr) suppressWarnings(expr)
set.seed(20262409)
for (rep in 1:30) {
  n <- sample(c(20, 40, 80), 1); p <- sample(2:4, 1); x <- matrix(rt(n * p, 4), n, p) %*% matrix(rnorm(p * p), p) + 1
  cm <- rep %% 3; has.wt <- as.numeric(rep %% 4 == 1); wt <- round(runif(n, 0, 2), 3); ctr <- round(rnorm(p), 2); nu <- c(5, 3, 8)[rep %% 3 + 1]
  maxit <- c(25, 6)[rep %% 2 + 1]; tol <- c(0.01, 1e-4)[rep %% 2 + 1]
  args <- list(x, nu = nu, maxit = maxit, tol = tol, center = if (cm == 0) TRUE else if (cm == 1) FALSE else ctr)
  if (has.wt == 1) args$wt <- wt
  r <- tryCatch(quiet(do.call(cov.trob, args)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, p, cm, has.wt, nu, maxit, tol); tail <- c(as.vector(x), if (has.wt == 1) wt, if (cm == 2) ctr)
  add("trob", c(a, 0, tail), wsum(r$cov)); add("trob", c(a, 1, tail), wsum(r$center)); add("trob", c(a, 2, tail), r$iter, 0, 0); add("trob", c(a, 3, tail), r$n.obs, 0, 0)
}
for (rep in 1:30) {
  n <- sample(c(25, 50, 90), 1); p <- sample(3:6, 1); inter <- as.numeric(rep %% 4 != 0)
  x <- matrix(rnorm(n * p), n, p) %*% (diag(p) + 0.4); y <- as.vector(x %*% rnorm(p)) + rnorm(n) + 2 * inter
  lam <- sort(c(0, runif(sample(1:4, 1), 0, 20))); d <- data.frame(y = y, x)
  f <- lm.ridge(as.formula(paste("y ~", if (inter == 1) "." else ". - 1")), d, lambda = lam)
  a <- c(n, p, inter, length(lam)); tail <- c(lam, as.vector(x), y)
  add("ridge", c(a, 0, tail), wsum(as.vector(coef(f)))); add("ridge", c(a, 1, tail), wsum(f$GCV)); add("ridge", c(a, 2, tail), f$kHKB); add("ridge", c(a, 3, tail), f$kLW); add("ridge", c(a, 4, tail), wsum(f$scales))
}
for (rep in 1:30) {
  n <- sample(c(15, 30, 60), 1); p <- sample(1:3, 1); inter <- as.numeric(rep %% 5 != 0); has.w <- as.numeric(rep %% 3 == 1)
  x <- matrix(rnorm(n * p), n, p); y <- as.vector(x %*% rnorm(p)) + rnorm(n, 0, 1.3) + inter; w <- round(runif(n, 0.3, 2.5), 3)
  if (has.w == 1 && rep %% 2 == 0) w[sample(n, 2)] <- 0
  d <- data.frame(y = y, x); fo <- as.formula(paste("y ~", if (inter == 1) "." else ". - 1"))
  f <- if (has.w == 1) lm(fo, d, weights = w) else lm(fo, d)
  r <- quiet(MASS:::lmwork(f)); a <- c(n, p, inter, has.w); tail <- c(as.vector(x), y, if (has.w == 1) w)
  add("stdres", c(a, 0, tail), wsum(r$stdres)); add("stdres", c(a, 1, tail), wsum(r$studres)); add("stdres", c(a, 2, tail), r$stddev)
}
for (n in 2:9) add("sdif", c(n, 0), wsum(contr.sdif(n)), 1e-14)
for (rep in 1:24) {
  link <- rep %% 5; dd <- data.frame(x = rnorm(60)); lk <- c("logit", "probit", "cloglog", "cauchit", "log")[link + 1]
  yy <- rbinom(60, 1, plogis(0.3 + 0.9 * dd$x)); g <- tryCatch(quiet(glm(yy ~ x, binomial(lk), dd)), error = function(e) NULL)
  if (is.null(g)) next
  pp <- c(0.5, 0.25, 0.9)[rep %% 3 + 1]; r <- tryCatch(quiet(dose.p(g, 1:2, pp)), error = function(e) NULL); if (is.null(r)) next
  b <- coef(g); V <- vcov(g)
  a <- c(link, pp, b[1], b[2], V[1, 1], V[1, 2], V[2, 2])
  add("dose", c(a, 0), as.numeric(r), 1e-9); add("dose", c(a, 1), as.numeric(attr(r, "SE")), 1e-9)
}
emit("mass_extra", "MASS", list(cases))
