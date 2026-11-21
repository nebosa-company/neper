# ghypfit: GeneralizedHyperbolic hyperbFit and nigFit (e.algo.stat.ghypfit) by Nelder-Mead, BFGS and L-BFGS-B from the package's start values.
# args: (seed, n, family 0 hyperb / 1 nig, start 0 BN / 1 US / 2 FN / 3 SL / 4 MoM, startMethod 0 NM / 1 BFGS, method 0 NM / 1 BFGS / 2 L-BFGS-B / 3 constrOptim, what,
#        generating mu, delta, alpha, beta, user start mu, delta, alpha, beta); the data are set.seed(seed); rhyperb / rnig(n, generating).
# what: 0..3 the fitted mu, delta, alpha, beta (1e-5); 4 the maximised log-likelihood (1e-7); 5 convergence code; 6 iterations (the function count, exact);
# 7..10 the start values on the normal scale (1e-8)
suppressMessages(library(GeneralizedHyperbolic))
cases <- list()
svn <- list(hyperb = c("BN", "US", "FN", "SL", "MoM"), nig = c("FN", "US", "FN", "FN", "MoM", "Cauchy"))
meths <- c("Nelder-Mead", "BFGS", "L-BFGS-B", "constrOptim", "nlm", "nlminb")
one <- function(seed, n, fam, kind, sm, method, gen) {
  set.seed(seed)
  x <- if (fam == 0) rhyperb(n, param = gen) else rnig(n, param = gen)
  us <- c(mean(x), sd(x), 1.5, 0.1)
  sv <- svn[[fam + 1]][kind + 1]
  smn <- c("Nelder-Mead", "BFGS")[sm + 1]
  fit <- tryCatch(suppressWarnings(capture.output(res <- (if (fam == 0) hyperbFit else nigFit)(x, paramStart = us, startValues = sv, startMethod = smn, method = meths[method + 1]))),
                  error = function(e) NULL)
  if (is.null(fit) || !exists("res") || !all(is.finite(res$param)) || !is.finite(res$maxLik)) return(NULL)
  list(res = res, us = us)
}
add <- function(seed, n, fam, kind, sm, method, gen, whats = c(0:4, 6, 7:10)) {
  r <- one(seed, n, fam, kind, sm, method, gen)
  if (is.null(r)) return(invisible())
  # a gradient method that ends against the delta boundary stops where finite-difference noise decides: not a defined result
  if (method > 0 && r$res$param[2] < 0.2) return(invisible())
  res <- r$res
  vals <- c(as.numeric(res$param), res$maxLik, if (length(res$conv)) res$conv else NA, res$iter, as.numeric(res$paramStart))
  tol <- c(1e-9, 1e-9, 1e-9, 1e-9, 1e-9, 0, 0, 1e-9, 1e-9, 1e-9, 1e-9)
  # BFGS/CG/L-BFGS-B stop on an optim finite-difference gradient (reltol/pgtol), so a last-bit besselK difference (R calls its own C besselK, not ported bit-for-bit) moves the end point: 2e-4 on the estimate, the likelihood stays at 1e-9
  if (method > 0 && method != 4) tol[1:4] <- 2e-4
  # nlminb reports its convergence code in iter (and nothing in conv), exact; a bound-active run ends where finite-difference noise decides
  if (method == 4) tol[1:4] <- 3e-3
  # nlm stops when the finite-difference gradient is under 1e-6, so its estimate is only that exact and besselK differing in the last bit can move one step: 3e-3 on the estimate, the step count to 2
  for (w in whats) {
    rl <- tol[w + 1]; ab <- tol[w + 1] * 1e-2
    # BFGS and L-BFGS-B stop on a finite-difference gradient: the function count is checked to 15 percent and 3 calls
    if (w == 6 && method == 4) { rl <- 0.1; ab <- 2 }
    if (w == 6 && method > 0 && method != 4 && method != 5) { rl <- 0.15; ab <- 3 }
    cases[[length(cases) + 1]] <<- case("ghypfit", c(seed, n, fam, kind, sm, method, w, gen, r$us), vals[w + 1], rel = rl, abs = ab)
  }
}
set.seed(20262104)
for (rep in 1:6) {
  n <- sample(120:180, 1); sd0 <- sample(1:100000, 1)
  gen <- c(rnorm(1), runif(1, 0.5, 2), runif(1, 1, 3)); gen <- c(gen, runif(1, -0.6, 0.6) * gen[3])
  for (m in 0:2) { add(sd0, n, 0, 0, 0, m, gen); add(sd0, n, 0, 2, 0, m, gen); add(sd0, n, 0, 1, 0, m, gen) }
  add(sd0, n, 0, 3, 0, 0, gen); add(sd0, n, 0, 3, 1, 0, gen); add(sd0, n, 0, 4, 0, 0, gen); add(sd0, n, 0, 4, 0, 2, gen)
  for (m in 0:2) { add(sd0, n, 1, 2, 0, m, gen); add(sd0, n, 1, 1, 0, m, gen) }
  add(sd0, n, 1, 4, 0, 0, gen)
  for (m in 0:2) add(sd0, n, 1, 5, 0, m, gen)
  for (kd in c(0, 1, 2)) { add(sd0, n, 0, kd, 0, 3, gen); add(sd0, n, 0, kd, 0, 4, gen) }
  for (kd in c(1, 2, 5)) add(sd0, n, 1, kd, 0, 4, gen)
  for (kd in c(0, 1, 2)) add(sd0, n, 0, kd, 0, 5, gen)
  for (kd in c(1, 2, 5)) add(sd0, n, 1, kd, 0, 5, gen)
  for (kd in c(1, 2, 5)) add(sd0, n, 1, kd, 0, 3, gen)
}
# "gigfit": (seed, n, start 0 LM / 1 GammaIG / 2 US, stand 0/1, what, generating chi, psi, lambda, user start chi, psi, lambda); the data are set.seed(seed); rgig(n, generating).
# what: 0 chi, 1 psi, 2 lambda (1e-5), 3 the maximised log-likelihood (1e-7), 4 convergence, 5 iterations (exact), 6..8 the start (log chi, log psi, lambda; 1e-8)
set.seed(20262105)
for (rep in 1:8) {
  n <- sample(120:200, 1); sd0 <- sample(1:100000, 1)
  gen <- c(runif(1, 0.5, 3), runif(1, 0.5, 3), c(runif(1, -1.5, 0.9), runif(1, 1.1, 2.5))[sample(1:2, 1)])
  set.seed(sd0); x <- rgig(n, gen[1], gen[2], gen[3])
  us <- c(1.2, 1.1, 0.7)
  for (kind in 0:2) for (stand in 0:1) for (mm in 0:1) {
    sv <- c("LM", "GammaIG", "US")[kind + 1]
    fit <- tryCatch(suppressWarnings(gigFit(x, paramStart = us, startValues = sv, method = c("Nelder-Mead", "nlm")[mm + 1], stand = stand == 1)), error = function(e) NULL)
    if (is.null(fit) || !all(is.finite(fit$param)) || !is.finite(fit$maxLik)) next
    # an nlm run that leaves the likelihood ridge (a parameter outside 1e-3 .. 1e3 on a flat surface) ends where finite-difference noise decides: not a defined result
    if (mm == 1 && (any(abs(fit$param) > 1e3) || any(abs(fit$param[1:2]) < 1e-3))) next
    # R's gigFit reads the conv and iter of an nlm result at indices that do not exist: both are empty or NA, so only the fit is compared for nlm
    vals <- c(as.numeric(fit$param), fit$maxLik, if (length(fit$conv)) fit$conv else NA, fit$iter, as.numeric(fit$paramStart))
    tol <- c(1e-9, 1e-9, 1e-9, 1e-9, 0, 0, 1e-9, 1e-9, 1e-9)
    # nlm stops on a finite-difference gradient under 1e-6 and a last-bit besselK difference moves it a step: 1e-6 on its estimate and likelihood
    if (mm == 1) tol[1:4] <- 1e-6
    # the GammaIG start is two MASS::fitdistr gamma fits by optim BFGS on a finite-difference gradient: a last-bit lgamma difference moves its end point by 2e-9 relative, and the fit that starts there by 5e-8
    if (kind == 1) tol[c(1:4, 8:9)] <- pmax(tol[c(1:4, 8:9)], 1e-7)
    for (w in 0:8) { if (mm == 1 && w %in% 4:5) next; cases[[length(cases) + 1]] <- case("gigfit", c(sd0, n, kind, stand + 2 * mm, w, gen, us), vals[w + 1], rel = tol[w + 1], abs = tol[w + 1] * 1e-2) }
  }
}
emit("ghypfit", "GeneralizedHyperbolic", list(cases))
