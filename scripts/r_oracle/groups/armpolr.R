# armpolr: bayespolr, the proportional odds model with t priors.
#   "bpolr" (n, pc, J, method 0 logistic 1 probit 2 cloglog 3 cauchit, scaled, has weights, prior.mean, prior.scale, prior.df, y (category 1..J), X row-major, [weights], which) with
#   which 0 beta, 1 zeta, 2 deviance, 3 f.evals, 4 g.evals, 5 Hessian (row-major), 6 fitted.values (row-major), 7 vcov (row-major, in zeta), 8 the standard errors of display;
#   a vector answer is the weighted sum 1 * v[1] + 2 * v[2] + ...
suppressMessages(library(arm))
cases <- list()
set.seed(20262300)
meths <- c("logistic", "probit", "cloglog", "cauchit")
nfit <- 0
for (rep in 1:32) {
  n <- sample(60:110, 1); pc <- sample(1:3, 1); J <- sample(3:5, 1); m <- (rep - 1) %% 4
  X <- matrix(round(rnorm(n * pc), 3), n, pc); if (pc >= 2 && rep %% 3 == 0) X[, 2] <- rbinom(n, 1, 0.5)
  lat <- as.vector(X %*% runif(pc, -1, 1)) + rlogis(n); cuts <- sort(runif(J - 1, -1.5, 1.5)); y <- as.integer(cut(lat, c(-Inf, cuts, Inf)))
  if (length(unique(y)) < J) next
  sc <- rep %% 5 != 0; wf <- rep %% 4 == 0; w <- if (wf) sample(1:3, n, TRUE) else NULL
  pmn <- c(0, 0, 0.3, -0.2)[rep %% 4 + 1]; psc <- c(2.5, 1.5, 4, 2.5)[rep %% 4 + 1]; pdf <- c(1, 3, Inf, 7)[rep %% 4 + 1]
  d <- data.frame(y = factor(y, ordered = TRUE), X); names(d) <- c("y", paste0("v", seq_len(pc)))
  f <- tryCatch(suppressWarnings(bayespolr(y ~ ., data = d, weights = w, method = meths[m + 1], prior.mean = pmn, prior.scale = psc, prior.df = pdf, scaled = sc, Hess = TRUE)), error = function(e) NULL)
  if (is.null(f) || f$convergence != 0) next
  nfit <- nfit + 1
  vc <- unname(vcov(f)); np <- pc + J - 1
  v <- list(unname(coef(f)), unname(f$zeta), f$deviance, unname(f$niter[1]), unname(f$niter[2]), as.vector(t(unname(f$Hessian))), as.vector(t(unname(f$fitted.values))), as.vector(t(vc)), sqrt(diag(vc)))
  tol <- list(c(1e-6, 1e-8), c(1e-6, 1e-8), c(1e-8, 1e-8), c(0.1, 3), c(0.1, 3), c(1e-4, 1e-6), c(1e-6, 1e-8), c(1e-4, 1e-6), c(1e-5, 1e-7))
  pre <- c(n, pc, J, m, sc, wf, pmn, psc, pdf, y, as.vector(t(X)), if (wf) w)
  for (wh in 1:9) { vv <- v[[wh]]; cases[[length(cases) + 1]] <- case("bpolr", c(pre, wh - 1), sum(seq_along(vv) * vv), rel = tol[[wh]][1], abs = tol[[wh]][2]) }
  # sim() on the fit: "simpolr" (seed, nsims, <pre as above>, draw): draw i is the weighted sum of c(coef, zeta) of draw i, equal draw by draw. Equality draw by draw needs the covariance
  # to be R's to the last bits, because the sign of an eigenvector LAPACK returns flips with a perturbation of 1e-13; the fit here is, except where R's x87 exp lands one bit away from the
  # round-twice model of armx87 (seed 62116, a cloglog fit with five categories), which is left out of the draw by draw cases and checked by "simpolrz": the same draw, projected on the
  # eigenvectors of the covariance in units of their standard deviation, absolute values (what the sign of an eigenvector cannot change), weighted 1, 2, ...
  sd0 <- sample(1:100000, 1); ns <- 3; set.seed(sd0); sm <- sim(f, ns)
  ev <- eigen(vcov(f), symmetric = TRUE); mu <- c(coef(f), f$zeta)
  for (i in 1:ns) {
    vv <- c(sm@coef[i, ], sm@zeta[i, ])
    if (!(sd0 %in% c(62116))) cases[[length(cases) + 1]] <- case("simpolr", c(sd0, ns, pre, i - 1), sum(seq_along(vv) * vv), rel = 1e-6, abs = 1e-8)
    zz <- abs(drop(t(ev$vectors) %*% (vv - mu)) / sqrt(ev$values))
    cases[[length(cases) + 1]] <- case("simpolrz", c(sd0, ns, pre, i - 1), sum(seq_along(zz) * zz), rel = 1e-6, abs = 1e-8)
  }
}
message("fits: ", nfit)
emit("armpolr", "arm", list(cases))
