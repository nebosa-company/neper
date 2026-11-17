# glmnet beyond the first group: cox, multinomial, and the cv, relax and predict pieces.
# Common head of every case (the fixture parses it): (n, p, alpha, std, nl, hw, hb, ho, lambda[nl], vf[p]) then the family data,
# X[n p] column-major, w[n * hw], lower[p * hb], upper[p * hb], offset[n * ho * (cols)], and the query.
suppressMessages({library(glmnet); library(survival)})
cases <- list()
head_ <- function(n, p, al, std, lam, hw, hb, ho, vf) c(n, p, al, std, length(lam), hw, hb, ho, lam, vf)
cq <- function(fn, hd, dat, X, w, lo, up, off, qy, want, rel = 1e-5, abs = 1e-6) case(fn, c(hd, dat, X, w, lo, up, off, qy), want, rel = rel, abs = abs)
brk <- function() "breslow"

# cox: data = (time[n], status[n]); query = (k, j); coefficient j (0-based, no intercept) at lambda k
set.seed(20261117)
for (rep in 1:14) {
  n <- sample(50:110, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  tm <- round(rexp(n, exp(0.5 * X[, 1] - 0.5 * X[, 2])), 1) + 0.1; st <- rbinom(n, 1, 0.8)
  alpha <- c(1, 0.5, 0.2, 0.9, 0)[(rep %% 5) + 1]; std <- rep %% 3 != 0
  vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  hw <- as.integer(rep %% 5 == 1); w <- if (hw) round(runif(n, 0.3, 3), 2) else numeric(0)
  ho <- as.integer(rep %% 5 == 2); off <- if (ho) round(rnorm(n, 0, 0.4), 2) else numeric(0)
  hb <- as.integer(rep %% 5 == 3); lo <- if (hb) round(-runif(p, 0, 1), 2) else numeric(0); up <- if (hb) round(runif(p, 0, 1), 2) else numeric(0)
  y <- Surv(tm, st)
  a0 <- list(x = X, y = y, family = "cox", alpha = alpha, standardize = std, penalty.factor = vf, cox.ties = "breslow")
  if (hw) a0$weights <- w; if (ho) a0$offset <- off; if (hb) { a0$lower.limits <- lo; a0$upper.limits <- up }
  f0 <- suppressWarnings(do.call(glmnet, a0)); L <- length(f0$lambda)
  lam <- f0$lambda[unique(round(seq(1, L, length.out = 7)))]
  a1 <- a0; a1$lambda <- lam; a1$thresh <- 1e-14
  f <- suppressWarnings(do.call(glmnet, a1)); cf <- as.matrix(coef(f))
  hd <- head_(n, p, alpha, std, lam, hw, hb, ho, vf)
  for (k in c(2, 4, length(lam))) for (j in 1:p) cases[[length(cases) + 1]] <- cq("cox", hd, c(tm, st), X, w, lo, up, off, c(k - 1, j), cf[j, k])
  # the automatic path and its length
  cases[[length(cases) + 1]] <- cq("coxlen", hd, c(tm, st), X, w, lo, up, off, 0, L, rel = 0, abs = 0.5)
  for (k in c(1, 2, 7, L)) cases[[length(cases) + 1]] <- cq("coxlam", hd, c(tm, st), X, w, lo, up, off, k - 1, f0$lambda[k], rel = 1e-9, abs = 1e-12)
}

emit("glmnet_ext", "glmnet", list(cases))
