# hetGP homoskedastic models: mleHomGP (optimised, partly known and fully known hyperparameters, three kernels, replicates,
# auto_bounds and user bounds), predict (mean, sd2, nugs, cov), update (maxit 0 and refit), crit_EI and crit_logEI.
#   args: header of 16 values (N, d, m, ctype 0/1/2, known_theta, known_g, known_beta0, g, beta0, user_bounds, maxit, mp, nnew,
#   maxit_up, has_cst, cst), then lower[d], upper[d], theta[d], X[N*d] row-major, Z[N], Xt[m*d], Xp[mp*d], Xn[nnew*d], Zn[nnew]
#   fn: theta g nu ll beta0 mean sd2 nugs cov ei logei lo up (vectors are weighted by position)
suppressMessages(library(hetGP))
cases <- list()
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20270301)
ctn <- c("Gaussian", "Matern5_2", "Matern3_2")
rm <- function(M) as.vector(t(M))
mid <- 0
# optimised fits whose L-BFGS-B path leaves the optimum a few 1e-8 away from R's (rounding in the Cholesky order moves the stopping
# iterate inside factr 1e7); every other fit equals R at 1e-9
loose <- c(24, 28)
doit <- function(N, d, m, ct, kt, kg, kb, user, maxit, mp, nnew, maxit_up, has_cst, tol_rel, tol_abs, reps) {
  force(N); force(d); force(m)
  mid <<- mid + 1
  if (mid %in% loose) { tol_rel <- 1e-6; tol_abs <- 1e-8 }
  n0 <- max(4, round(N * (if (reps) 0.5 else 1)))
  X0 <- matrix(runif(n0 * d), n0)
  X <- if (reps) X0[c(1:n0, sample(n0, N - n0, replace = TRUE)), , drop = FALSE] else X0[1:N, , drop = FALSE]
  X <- X[sample(nrow(X)), , drop = FALSE]
  Z <- sin(3 * X[, 1]) + rowSums(X) + rnorm(N, 0, 0.1 + 0.2 * X[, 1])
  Xt <- matrix(runif(m * d), m); Xp <- matrix(runif(mp * d), mp)
  th <- runif(d, 0.15, 1.2); g <- runif(1, 0.005, 0.1); b0 <- runif(1, 0.5, 2)
  lower <- runif(d, 0.02, 0.1); upper <- lower + runif(d, 1, 3)
  known <- list(); if (kt) known$theta <- th; if (kg) known$g <- g; if (kb) known$beta0 <- b0
  args <- list(X = X, Z = Z, covtype = ctn[ct + 1], known = known, maxit = maxit)
  if (user) { args$lower <- lower; args$upper <- upper }
  mo <- tryCatch(suppressWarnings(do.call(mleHomGP, args)), error = function(e) NULL); if (is.null(mo)) return(invisible())
  Xn <- matrix(0, 0, d); Zn <- numeric(0)
  if (nnew > 0) {
    k <- sample(nrow(mo$X0), min(2, nnew), replace = TRUE)
    Xn <- rbind(mo$X0[k, , drop = FALSE], matrix(runif((nnew - length(k)) * d), ncol = d)); Zn <- rnorm(nnew, mean(Z), 0.3)
    mo <- tryCatch(suppressWarnings(update(mo, Xnew = Xn, Znew = Zn, maxit = maxit_up)), error = function(e) NULL); if (is.null(mo)) return(invisible())
  }
  cst <- if (has_cst) quantile(Z, 0.3, names = FALSE) else 0
  pr <- suppressWarnings(predict(mo, Xt, xprime = if (mp > 0) Xp else NULL))
  hd <- c(N, d, m, ct, kt, kg, kb, g, b0, user, maxit, mp, nnew, maxit_up, has_cst, cst)
  a <- c(hd, lower, upper, th, rm(X), Z, rm(Xt), rm(Xp), rm(Xn), Zn)
  add <- function(fn, want, rel = tol_rel, abs = tol_abs) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = rel, abs = abs)
  add("theta", ws(mo$theta)); add("g", mo$g); add("nu", mo$nu_hat); add("beta0", mo$beta0)
  if (nnew == 0) { add("ll", as.numeric(mo$ll)) }
  add("mean", ws(pr$mean)); add("sd2", ws(pr$sd2)); add("nugs", ws(pr$nugs))
  if (mp > 0) add("cov", ws(rm(pr$cov)))
  ei <- suppressWarnings(crit_EI(Xt, mo, cst = if (has_cst) cst else NULL)); add("ei", ws(ei))
  le <- suppressWarnings(crit_logEI(Xt, mo, cst = if (has_cst) cst else NULL)); if (all(is.finite(le))) add("logei", ws(le))
  if (!user && !kt) { add("lo", ws(mo$used_args$lower)); add("up", ws(mo$used_args$upper)) }
}

# fully known hyperparameters, three kernels
for (rep in 1:9) doit(sample(8:30, 1), sample(1:3, 1), sample(2:5, 1), rep %% 3, 1, 1, 0, 0, 100, sample(0:2, 1), 0, 0, rep %% 2, 1e-9, 1e-10, rep > 4)
# optimised theta and g
for (rep in 1:18) doit(sample(10:35, 1), sample(1:3, 1), 4, rep %% 3, 0, 0, 0, rep %% 2, 100, 2, 0, 0, rep %% 2, 1e-9, 1e-10, rep %% 3 != 0)
# known g only, known theta only, known beta0
for (rep in 1:3) doit(sample(10:25, 1), sample(1:2, 1), 3, rep %% 3, 0, 1, 0, 0, 100, 0, 0, 0, 0, 1e-9, 1e-10, TRUE)
for (rep in 1:3) doit(sample(10:25, 1), sample(1:2, 1), 3, rep %% 3, 1, 0, 0, 0, 100, 0, 0, 0, 0, 1e-9, 1e-10, TRUE)
for (rep in 1:3) doit(sample(10:25, 1), sample(1:2, 1), 3, rep %% 3, 0, 0, 1, 0, 100, 2, 0, 0, 0, 1e-9, 1e-10, TRUE)
# update with maxit 0 (rank-one in R) and with a refit
for (rep in 1:6) doit(sample(10:25, 1), sample(1:2, 1), 3, rep %% 3, 1, 1, 0, 0, 100, 2, sample(1:4, 1), 0, 0, 1e-9, 1e-10, FALSE)
for (rep in 1:3) doit(sample(10:25, 1), sample(1:2, 1), 3, rep %% 3, 0, 0, 0, 0, 100, 2, sample(1:4, 1), 100, 0, 1e-9, 1e-10, TRUE)
emit("hetgp", "hetGP", list(cases))
