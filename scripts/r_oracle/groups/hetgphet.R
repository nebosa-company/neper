# hetGP mleHetGP (joint thetas, logN, residual initialisation, penalty, checkHom) with predict.hetGP, update.hetGP (maxit = 0) and the
# expected improvements.
#   args: header of 20 values (N, d, m, ctype 0/1/2, known_theta, known_g, known_kt, known_beta0, g, kt, beta0, user_bounds, maxit, mp,
#   has_cst, cst, known_Delta, slot17, nnew, 0), then lower[d], upper[d], theta[d], X[N*d] row-major, Z[N], Xt[m*d], Xp[mp*d],
#   Delta[n], Xn[nnew*d], Zn[nnew]; slot17 is hom_ll for llpen / llraw / grad
#   fn: llpen llraw grad (hetGP's logLikHet and dlogLikHet at given parameters), and for a
#   model ishet theta g kt nu ll llnp beta0 delta lam mean sd2 nugs sd2var cov ei logei (vectors are weighted by position)
# L-BFGS-B on the 40-odd parameters of a heteroskedastic fit is chaotic: both optimisers follow the same path for the first iterations
# (cases with maxit 6 below), then rounding differences grow, so a converged fit is checked through R's solution fed back as known
# hyperparameters, where nothing is optimised.
suppressMessages(library(hetGP))
cases <- list()
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20270402)
ctn <- c("Gaussian", "Matern5_2", "Matern3_2")
rm <- function(M) as.vector(t(M))
mid <- 0
# n0 sites with 1 to maxrep replicates each, noise that grows with x1
mkdata <- function(n0, maxrep, d) {
  X0 <- matrix(runif(n0 * d), n0)
  mu <- if (maxrep > 1) sample(1:maxrep, n0, replace = TRUE) else rep(1, n0)
  X <- X0[rep(1:n0, times = mu), , drop = FALSE]
  N <- nrow(X)
  X <- X[sample(N), , drop = FALSE]
  Z <- sin(3 * X[, 1]) + rowSums(X) + rnorm(N, 0, 0.05 + 0.5 * X[, 1]^2)
  list(X = X, Z = Z, N = N)
}
# every output of a model (hetGP or the homoskedastic fallback), against the argument vector a
outputs <- function(a, mo, Xt, Xp, mp, has_cst, cst, nnew, rel, abs, sdv_rel) {
  het <- inherits(mo, "hetGP")
  add <- function(fn, want, r = rel, ab = abs) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = r, abs = ab)
  pr <- suppressWarnings(predict(mo, Xt, xprime = if (mp > 0) Xp else NULL))
  add("ishet", as.numeric(het), 0, 0)
  add("theta", ws(mo$theta)); add("g", mo$g); add("nu", mo$nu_hat); add("beta0", mo$beta0)
  if (!is.null(mo$ll) && nnew == 0) add("ll", as.numeric(mo$ll))
  if (het) {
    add("kt", mo$k_theta_g); if (nnew == 0) add("llnp", mo$ll_non_pen); add("delta", ws(mo$Delta)); add("lam", ws(mo$Lambda))
    # sd2var = nu*nuvar*(1 - kg Kgi kg + ...) cancels: R with solve() instead of chol2inv differs from R by up to ~2e-10*cond(Kg) in relative terms (the 1 - q term cancels), so the tolerance scales with it
    Xg <- if (is.null(mo$pX)) mo$X0 else mo$pX
    cg <- kappa(hetGP::cov_gen(X1 = Xg, theta = mo$theta_g, type = mo$covtype) + diag(mo$eps + mo$g / mo$mult[seq_len(nrow(Xg))]), exact = TRUE)
    add("sd2var", ws(suppressWarnings(predict(mo, Xt, noise.var = TRUE)$sd2var)), r = max(sdv_rel, 3e-10 * cg))
  }
  add("mean", ws(pr$mean)); add("sd2", ws(pr$sd2)); add("nugs", ws(pr$nugs))
  if (mp > 0) add("cov", ws(rm(pr$cov)))
  ei <- suppressWarnings(crit_EI(Xt, mo, cst = if (has_cst) cst else NULL)); add("ei", ws(ei))
  le <- suppressWarnings(crit_logEI(Xt, mo, cst = if (has_cst) cst else NULL)); if (all(is.finite(le))) add("logei", ws(le))
}
# a model at fixed hyperparameters, optionally updated with new points (maxit = 0)
record <- function(dat, ct, d, m, mp, has_cst, th, g, k, b0, kb, dl, lower, upper, slot17, tol_rel, tol_abs, Xt, Xp, tol_sdv, nnew = 0) {
  known <- list(theta = th, g = g, k_theta_g = k, Delta = dl); if (kb) known$beta0 <- b0
  mo <- suppressWarnings(mleHetGP(dat$X, dat$Z, covtype = ctn[ct + 1], known = known))
  Xn <- matrix(0, 0, d); Zn <- numeric(0)
  if (nnew > 0) {
    k1 <- sample(nrow(mo$X0), 2)
    Xn <- rbind(mo$X0[k1, , drop = FALSE], matrix(runif((nnew - 3) * d), ncol = d)); Xn <- rbind(Xn, Xn[3, , drop = FALSE]); Zn <- rnorm(nnew, mean(dat$Z), 0.3)
    mo <- suppressWarnings(update(mo, Xnew = Xn, Znew = Zn, maxit = 0))
  }
  cst <- if (has_cst) quantile(dat$Z, 0.3, names = FALSE) else 0
  hd <- c(dat$N, d, m, ct, 1, 1, 1, kb, g, k, b0, 0, 100, mp, has_cst, cst, 1, slot17, nnew, 0)
  a <- c(hd, lower, upper, th, rm(dat$X), dat$Z, rm(Xt), rm(Xp), dl, rm(Xn), Zn)
  outputs(a, mo, Xt, Xp, mp, has_cst, cst, nnew, tol_rel, tol_abs, tol_sdv)
}
# logLikHet and dlogLikHet at random parameters
evalpt <- function(n0, maxrep, d, ct, pen_on) {
  dat <- mkdata(n0, maxrep, d)
  el <- find_reps(dat$X, dat$Z, return.Zlist = FALSE)
  n <- nrow(el$X0)
  th <- runif(d, 0.15, 1.2); g <- runif(1, 0.01, 0.9); k <- runif(1, 1, 6); dl <- rnorm(n, -2, 0.7)
  raw <- hetGP:::logLikHet(el$X0, el$Z0, el$Z, el$mult, dl, th, g, k_theta_g = k, logN = TRUE, covtype = ctn[ct + 1], penalty = FALSE)
  hom_ll <- if (pen_on) raw - 3 else raw + 3
  pen <- hetGP:::logLikHet(el$X0, el$Z0, el$Z, el$mult, dl, th, g, k_theta_g = k, logN = TRUE, covtype = ctn[ct + 1], penalty = TRUE, hom_ll = hom_ll)
  gr <- hetGP:::dlogLikHet(el$X0, el$Z0, el$Z, el$mult, dl, th, g, k_theta_g = k, logN = TRUE, covtype = ctn[ct + 1], penalty = TRUE, hom_ll = hom_ll)
  lower <- rep(0.05, d); upper <- rep(2, d)
  hd <- c(dat$N, d, 1, ct, 0, 0, 0, 0, g, k, 0, 1, 100, 0, 0, 0, 0, hom_ll, 0, 0)
  a <- c(hd, lower, upper, th, rm(dat$X), dat$Z, rm(matrix(0.5, 1, d)), numeric(0), dl)
  cases[[length(cases) + 1]] <<- case("llraw", a, raw, rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <<- case("llpen", a, pen, rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <<- case("grad", a, ws(gr), rel = 1e-8, abs = 1e-9)
  cat("eval", n0, maxrep, d, ct, pen_on, "\n", file = stderr())
}
# optimised fits: the first iterations (maxit 6) against R, and R's converged
# hyperparameters fed back as known
fitcase <- function(n0, maxrep, d, m, ct, user, mp, has_cst) {
  mid <<- mid + 1
  dat <- mkdata(n0, maxrep, d)
  Xt <- matrix(runif(m * d), m); Xp <- matrix(runif(mp * d), mp)
  lower <- runif(d, 0.05, 0.15); upper <- lower + runif(d, 1, 2)
  cst <- if (has_cst) quantile(dat$Z, 0.3, names = FALSE) else 0
  run <- function(maxit) {
    args <- list(X = dat$X, Z = dat$Z, covtype = ctn[ct + 1], maxit = maxit)
    if (user) { args$lower <- lower; args$upper <- upper }
    tryCatch(suppressWarnings(do.call(mleHetGP, args)), error = function(e) NULL)
  }
  mo6 <- run(6)
  if (!is.null(mo6)) {
    hd <- c(dat$N, d, m, ct, 0, 0, 0, 0, 0.1, 1, 1, user, 6, mp, has_cst, cst, 0, 0, 0, 0)
    a <- c(hd, lower, upper, rep(0.5, d), rm(dat$X), dat$Z, rm(Xt), rm(Xp), numeric(0))
    outputs(a, mo6, Xt, Xp, mp, has_cst, cst, 0, 1e-6, 1e-8, 1e-8)
  }
  mo <- run(100); if (is.null(mo)) return(invisible())
  het <- inherits(mo, "hetGP")
  cat(mid, "het", het, "N", dat$N, "d", d, "ct", ct, "\n", file = stderr())
  if (het) record(dat, ct, d, m, mp, has_cst, mo$theta, mo$g, mo$k_theta_g, 1, FALSE, mo$Delta, lower, upper, 0, 1e-6, 1e-8, Xt, Xp, 1e-8)
}
# known hyperparameters drawn at random, with and without a known mean
knowncase <- function(n0, maxrep, d, m, ct, kb, mp, has_cst, nnew = 0) {
  dat <- mkdata(n0, maxrep, d)
  nu0 <- nrow(find_reps(dat$X, dat$Z, return.Zlist = FALSE)$X0)
  th <- runif(d, 0.15, 1.2); g <- runif(1, 0.005, 0.5); k <- runif(1, 1, 5); b0 <- runif(1, 0.5, 2); dl <- rnorm(nu0, -2, 0.5)
  Xt <- matrix(runif(m * d), m); Xp <- matrix(runif(mp * d), mp)
  record(dat, ct, d, m, mp, has_cst, th, g, k, b0, kb, dl, rep(0.05, d), rep(2, d), 0, 1e-9, 1e-10, Xt, Xp, 1e-9, nnew)
  cat("known", n0, maxrep, d, ct, "\n", file = stderr())
}

for (rep in 1:9) knowncase(sample(8:20, 1), if (rep > 3) 4 else 1, sample(1:3, 1), 4, rep %% 3, rep > 6, 2, rep %% 2)
for (rep in 1:9) knowncase(sample(8:16, 1), if (rep > 3) 3 else 1, sample(1:3, 1), 4, rep %% 3, rep > 6, 2, rep %% 2, sample(4:6, 1))
for (rep in 1:12) evalpt(sample(8:16, 1), if (rep > 6) 3 else 1, sample(1:3, 1), rep %% 3, rep %% 2 == 0)
for (rep in 1:7) fitcase(sample(10:16, 1), 4, sample(1:2, 1), 4, rep %% 3, rep %% 2, 2, rep %% 2)
for (rep in 1:4) fitcase(sample(22:30, 1), 1, sample(1:2, 1), 4, rep %% 3, 1, 0, TRUE)
emit("hetgphet", "hetGP", list(cases))
