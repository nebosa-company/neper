# poLCA latent class analysis and latent class regression at the package defaults (maxiter 1000, tol 1e-10, calc.se TRUE).
#   "fit" args (n, J, R, q, nrep, seed, na.rm, length(start), start (vectorized probs.start), y[n*J] row-major 1-based with 0 for NA, x[n*q] row-major) want llik;
#   set.seed(seed) runs right before poLCA. The fixture keeps that fit for the "q" cases after it: args (code, index), index 1-based for the vector codes.
#   codes: 1 numiter, 2 npar, 3 aic, 4 bic, 5 Gsq, 6 Chisq, 7 resid.df, 8 Nobs, 9 N, 10 entropy, 11 eflag, 12 cells in predcell, 13 sum(predclass), 14 sum(predclass * i),
#   20 probs, 21 P, 22 probs.se, 23 P.se, 24 coeff, 25 coeff.se, 26 coeff.V, 27 attempts, 28 probs.start (the R RNG draws),
#   30 sum(posterior * i) (row-major), 31 sum(observed * i), 32 sum(expected * i) (unrounded), 33 sum(cell pattern * i) (row-major)
# Tolerance 1e-9 relative (1e-12 absolute) for the real values, exact for the counts; Gsq and Chisq also pass within 1e-10 absolute, because near a saturated fit they are
# sums of freq * log(freq / fit) with fit within 1e-10 of freq, and one rounding of a fitted cell moves them by about 1e-12.
suppressMessages(library(poLCA))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel, abs)
vec <- function(probs) unlist(lapply(probs, function(m) as.vector(t(m))))
run <- function(d, X, R, nrep, seed, na.rm, st) {
  force(nrep); force(seed); force(st); force(na.rm)
  J <- ncol(d); n <- nrow(d); q <- if (is.null(X)) 0 else ncol(X)
  dd <- d
  rhs <- "1"
  if (q > 0) { xd <- as.data.frame(X); names(xd) <- paste0("x", 1:q); dd <- cbind(d, xd); rhs <- paste(names(xd), collapse = " + ") }
  fm <- as.formula(paste("cbind(", paste(names(d), collapse = ","), ") ~", rhs))
  set.seed(seed)
  f <- tryCatch(suppressMessages(poLCA(fm, dd, nclass = R, nrep = nrep, probs.start = st, na.rm = na.rm, verbose = FALSE)), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(f)) return(FALSE)
  if (any(!is.finite(unlist(f$probs.se))) || any(!is.finite(f$P.se))) return(FALSE)
  # restarts that reach the best log-likelihood to within the convergence tolerance tie, and which one R keeps is decided by the last bits of the sums
  if (sum(abs(f$attempts - f$llik) < 1e-6) > 1) return(FALSE)
  # so does a fit whose last log-likelihood change lies within 1e-12 of tol: whether it stops there is decided by the last bit of the long double sum
  for (tt in c(0.99e-10, 1.01e-10)) {
    set.seed(seed)
    g <- suppressWarnings(suppressMessages(poLCA(fm, dd, nclass = R, nrep = nrep, probs.start = st, na.rm = na.rm, verbose = FALSE, tol = tt)))
    if (g$numiter != f$numiter) return(FALSE)
  }
  dz <- as.matrix(d); dz[is.na(dz)] <- 0
  sv <- if (is.null(st)) numeric(0) else vec(st)
  add("fit", c(n, J, R, q, nrep, seed, as.numeric(na.rm), length(sv), sv, as.vector(t(dz)), if (q > 0) as.vector(t(X)) else numeric(0)), f$llik)
  ex <- function(code, v) add("q", c(code, 0), v, 0, 0)
  ap <- function(code, v) add("q", c(code, 0), v)
  ex(1, f$numiter); ex(2, f$npar); ap(3, f$aic); ap(4, f$bic); add("q", c(5, 0), f$Gsq, 1e-9, 1e-10); add("q", c(6, 0), f$Chisq, 1e-9, 1e-10); ex(7, f$resid.df); ex(8, f$Nobs); ex(9, f$N)
  ap(10, poLCA.entropy(f)); ex(11, as.numeric(f$eflag)); ex(12, nrow(f$predcell)); ex(13, sum(f$predclass)); ex(14, sum(f$predclass * seq_along(f$predclass)))
  each <- function(code, v) for (i in seq_along(v)) add("q", c(code, i), v[i])
  each(20, vec(f$probs)); each(21, f$P); each(22, vec(f$probs.se)); each(23, f$P.se)
  if (q > 0) { each(24, as.vector(f$coeff)); each(25, as.vector(f$coeff.se)); each(26, as.vector(f$coeff.V)) }
  each(27, f$attempts); each(28, vec(f$probs.start))
  pm <- as.vector(t(f$posterior)); ap(30, sum(pm * seq_along(pm)))
  dc <- as.matrix(f$predcell[, 1:J]); storage.mode(dc) <- "double"
  tot <- if (na.rm) f$N else f$Nobs
  fitc <- as.vector(tot / .Machine$double.xmax * (poLCA:::poLCA.ylik.C(poLCA:::poLCA.vectorize(f$probs), dc) %*% f$P))
  ap(31, sum(f$predcell$observed * seq_along(fitc))); ap(32, sum(fitc * seq_along(fitc)))
  cv <- as.vector(t(dc)); ap(33, sum(cv * seq_along(cv)))
  TRUE
}
gen <- function(n, J, R, ncat, cl, shape) {
  th <- lapply(seq_len(J), function(j) t(sapply(seq_len(R), function(r) { p <- rgamma(ncat[j], shape); p / sum(p) })))
  d <- as.data.frame(sapply(seq_len(J), function(j) sapply(cl, function(c) sample(ncat[j], 1, prob = th[[j]][c, ]))))
  names(d) <- paste0("y", seq_len(J))
  d
}
start <- function(d, R) lapply(seq_len(ncol(d)), function(j) { k <- max(d[, j], na.rm = TRUE); t(sapply(seq_len(R), function(r) { p <- runif(k, 0.2, 1); p / sum(p) })) })
ok <- function(d) all(sapply(d, function(v) length(unique(na.omit(v)))) >= 2)
set.seed(20271122)
# given starting probabilities, no covariates
for (rep in 1:14) {
  n <- sample(150:400, 1); J <- sample(3:5, 1); R <- sample(2:3, 1); ncat <- sample(2:3, J, TRUE)
  d <- gen(n, J, R, ncat, sample(1:R, n, TRUE, runif(R, 0.3, 1)), 1.0)
  if (!ok(d)) next
  st <- start(d, R); seed <- sample(1000:99999, 1)
  run(d, NULL, R, 1, seed, TRUE, st)
}
# random starts from the R RNG, best of nrep
for (rep in 1:36) {
  n <- sample(150:350, 1); J <- sample(3:5, 1); R <- sample(2:3, 1); ncat <- sample(2:3, J, TRUE)
  d <- gen(n, J, R, ncat, sample(1:R, n, TRUE), 1.0)
  if (!ok(d)) next
  run(d, NULL, R, sample(2:4, 1), sample(1000:99999, 1), TRUE, NULL)
}
# missing responses, kept (na.rm = FALSE) and dropped (na.rm = TRUE)
for (rep in 1:10) {
  n <- sample(200:400, 1); J <- sample(4:5, 1); R <- 2; ncat <- sample(2:3, J, TRUE)
  d <- gen(n, J, R, ncat, sample(1:R, n, TRUE, c(0.45, 0.55)), 1.5)
  for (j in 1:J) d[sample(n, round(n * 0.08)), j] <- NA
  if (!ok(d)) next
  narm <- rep %% 3 == 0
  st <- if (rep %% 2 == 0) NULL else start(if (narm) na.omit(d) else d, R)
  run(d, NULL, R, sample(1:2, 1), sample(1000:99999, 1), narm, st)
}
# latent class regression with covariates, given starts and random starts
for (rep in 1:22) {
  n <- sample(300:500, 1); J <- sample(4:5, 1); R <- sample(2:3, 1); q <- sample(1:2, 1); ncat <- sample(2:3, J, TRUE)
  X <- matrix(round(rnorm(n * q), 3), n, q)
  eta <- cbind(0, sapply(2:R, function(r) 0.2 * r + 0.9 * X[, 1]))
  pr <- exp(eta) / rowSums(exp(eta))
  cl <- apply(pr, 1, function(p) sample(R, 1, prob = p))
  d <- gen(n, J, R, ncat, cl, 1.5)
  if (!ok(d)) next
  st <- if (rep %% 2 == 0) NULL else start(d, R)
  run(d, X, R, sample(1:3, 1), sample(1000:99999, 1), TRUE, st)
}
emit("polca", "poLCA", list(cases))
