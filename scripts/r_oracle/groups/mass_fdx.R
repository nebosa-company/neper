# MASS fitdistr with fixed parameters, user starts, lower / upper bounds (L-BFGS-B) and forced methods.
# Tolerances: F and t 1e-5 (1e-6 fails 7 cases: flat df ridge amplifies one-ulp density differences at the BFGS stop point), negative binomial 1e-6, rest 1e-8; see mass_probe.R
#   "fdx" (kind 0 gamma 1 weibull 2 logistic 3 cauchy 4 nbinom 5 beta 6 F 7 chisq 8 t, n, free[3], fixed[3], use.start, start[3], bounded, lower[3], upper[3], method 0 auto 1 BFGS 2 NM 3 LBFGSB, which, x[n])
#   which 0 .. nf - 1 estimates, nf .. 2 nf - 1 standard errors, 2 nf the log-likelihood (nf = number of free parameters), 50 the position-weighted sum of vcov, 51 vcov[2] (column-major), 100 n
suppressMessages(library(MASS))
cases <- list()
set.seed(20262404)
pn <- list(c("shape", "rate"), c("shape", "scale"), c("location", "scale"), c("location", "scale"), c("size", "mu"), c("shape1", "shape2"), c("df1", "df2"), "df", c("m", "s", "df"))
dn <- c("gamma", "weibull", "logistic", "cauchy", "negative binomial", "beta", "f", "chi-squared", "t")
gen <- function(kind, n) switch(kind + 1, rgamma(n, 3, 1.5), rweibull(n, 2, 3), rlogis(n, 1, 2), rcauchy(n, 0.5, 1.2), rnbinom(n, size = 4, mu = 5), rbeta(n, 2.5, 4), rf(n, 7, 11), rchisq(n, 4), 1 + 2 * rt(n, 6))
defst <- list(NULL, NULL, NULL, NULL, NULL, c(2, 2), c(3, 3), 3, NULL)
# the likelihood is a sum of R-identical densities except negative binomial, F and t, whose last bits differ; optim stops at its reltol (1.5e-8) and the F and t degrees of freedom sit on a flat ridge of the likelihood (a last-bit change of the objective moves the stop by ~1e-5 relative): F and t 1e-4, negative binomial 1e-6, the rest 1e-8
rel_for <- function(kind, w, nf) if (kind %in% c(6, 8)) 1e-5 else if (kind == 4) 1e-6 else 1e-8
for (rep in 1:90) {
  kind <- rep %% 9; n <- sample(60:160, 1); x <- gen(kind, n)
  np <- length(pn[[kind + 1]]); free <- rep(1, np); fixed <- rep(0, np)
  scen <- (rep - 1) %/% 9 %% 5   # 0 plain start, 1 bounded, 2 one parameter fixed, 3 forced method, 4 bounded with a start
  bounded <- 0; lo <- rep(-1e308, 3); up <- rep(1e308, 3); method <- 0; use.start <- as.numeric(!is.null(defst[[kind + 1]]))
  args <- list(x, dn[kind + 1]); st <- defst[[kind + 1]]
  if (scen == 2 && np >= 2) {
    k <- np; free[k] <- 0; fixed[k] <- if (kind == 8) 6 else if (kind == 0) 1.5 else if (kind == 1) 3 else if (kind == 4) 5 else if (kind == 5) 4 else if (kind == 6) 11 else 2
    if (kind == 0) { free[2] <- 0; free[1] <- 1 }
    args[[pn[[kind + 1]][k]]] <- fixed[k]
  }
  if (scen == 3) { method <- if (np == 1) 1 else 2; args$method <- if (method == 1) "BFGS" else "Nelder-Mead" }
  if (scen == 1 || scen == 4) {
    bounded <- 1; method <- 0
    nfree <- sum(free); lo[1:np] <- 1e-3; up[1:np] <- 50; if (kind %in% c(2, 3, 8)) lo[1] <- -20
    if (kind == 5 || kind == 6 || kind == 7) { lo[1:np] <- 0.5; up[1:np] <- 30 }
    args$lower <- lo[seq_len(np)][free == 1]; args$upper <- up[seq_len(np)][free == 1]
  }
  if (scen == 4 && is.null(st)) {
    st <- switch(kind + 1, c(2, 1), c(1.5, 2.5), c(0, 1), c(0, 1), c(3, 4), NULL, NULL, NULL, c(0, 1.5, 8)); use.start <- 1
  }
  if (use.start == 1) { sl <- as.list(st[free == 1]); names(sl) <- pn[[kind + 1]][free == 1]; args$start <- sl }
  else st <- rep(0, 3)
  if (kind == 0 && scen == 2) next
  r <- tryCatch(suppressWarnings(do.call(fitdistr, args)), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik); nf <- sum(free)
  stv <- c(st, rep(0, 3))[1:3]
  fr <- c(free, rep(0, 3))[1:3]; fx <- c(fixed, rep(0, 3))[1:3]
  if (use.start == 1) { stf <- rep(0, 3); stf[seq_len(np)] <- st[seq_len(np)] } else stf <- rep(0, 3)
  for (w in 0:(2 * nf)) cases[[length(cases) + 1]] <- case("fdx", c(kind, n, fr, fx, use.start, stf, bounded, lo, up, method, w, x), v[w + 1], rel = rel_for(kind, w, nf), abs = 1e-6)
  if (rep %% 2 == 0) { # vcov (the weighted sum of all entries, an off-diagonal entry) and n.
    vc <- as.vector(r$vcov)
    cases[[length(cases) + 1]] <- case("fdx", c(kind, n, fr, fx, use.start, stf, bounded, lo, up, method, 50, x), sum(seq_along(vc) * vc), rel = rel_for(kind, 0, nf), abs = 1e-6)
    if (nf >= 2) cases[[length(cases) + 1]] <- case("fdx", c(kind, n, fr, fx, use.start, stf, bounded, lo, up, method, 51, x), vc[2], rel = rel_for(kind, 0, nf), abs = 1e-6)
    cases[[length(cases) + 1]] <- case("fdx", c(kind, n, fr, fx, use.start, stf, bounded, lo, up, method, 100, x), r$n, rel = 0, abs = 0)
  }
}
emit("mass_fdx", "MASS", list(cases))
