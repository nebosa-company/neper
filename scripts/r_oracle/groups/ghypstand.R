# ghypstand: GeneralizedHyperbolic hyperbFitStand ("fs") and hyperblm ("lm") (e.algo.stat.ghypstand).
# "fs" args: (seed, n, start 0 BN / 1 US / 2 MoM, startMethod 0 NM / 1 BFGS, method 0 NM / 1 BFGS / 2 L-BFGS-B / 3 constrOptim, what, generating mu, delta, alpha, beta,
#             user start mu, delta, alpha, beta); the data are set.seed(seed); rhyperb(n, generating). what: 0..3 mu, delta, alpha, beta (1e-5), 4 log-likelihood (1e-7),
#             5 convergence, 6 iterations (exact for Nelder-Mead; 15 percent for gradient methods), 7..8 the start (rho, zeta; 1e-8).
# "lm" args: (seed, n, method 0 NM / 1 BFGS, startStarts 0 BN / 2 MoM, startMethod 0 NM / 1 BFGS, what, b0, b1, b2, generating mu, delta, alpha, beta); the design is
#            x1 = seq(0, 1, length = n), x2 = ((7 i) %% 11) / 11, y = b0 + b1 x1 + b2 x2 + e with e = set.seed(seed); rhyperb(n, generating).
#            what: 0..2 the coefficients, 3..6 distributionParams (shift, delta, alpha, beta), 7 MLE, 8 convergence, 9 iterations, 10..13 residsParamStart.
suppressMessages(library(GeneralizedHyperbolic))
cases <- list()
meths <- c("Nelder-Mead", "BFGS", "L-BFGS-B", "constrOptim", "nlm", "nlminb")
svs <- c("BN", "US", "MoM")
smn <- c("Nelder-Mead", "BFGS")
addfs <- function(seed, n, kind, sm, method, gen) {
  set.seed(seed); x <- rhyperb(n, param = gen)
  us <- c(mean(x) + 0.2 * sd(x), 0.8 * sd(x), 1.5 / sd(x), 0.1 / sd(x))
  res <- NULL
  fit <- tryCatch(suppressWarnings(capture.output(res <- hyperbFitStand(x, paramStart = us, startValues = svs[kind + 1], startMethod = smn[sm + 1], method = meths[method + 1]))),
                  error = function(e) NULL)
  if (is.null(fit) || is.null(res) || !all(is.finite(res$param)) || !is.finite(res$maxLik) || abs(res$maxLik) > 1e300) return(invisible())
  if (method > 0 && res$param[2] < 0.2) return(invisible())
  rz <- tryCatch(suppressWarnings({
    xs <- (x - mean(x)) / sd(x)
    st <- GeneralizedHyperbolic:::hyperbFitStandStart(xs, startValues = svs[kind + 1], paramStart = c(us[1] - mean(x), us[2] / sd(x), sd(x) * us[3], sd(x) * us[4]), startMethodMoM = smn[sm + 1])
    as.numeric(st$paramStart)[1:2]}), error = function(e) c(NA, NA))
  vals <- c(as.numeric(res$param), res$maxLik, res$conv, res$iter, rz)
  tol <- c(1e-5, 1e-5, 1e-5, 1e-5, 1e-7, 0, 0, 1e-8, 1e-8)
  if (method > 0) tol[1:4] <- 2e-4
  if (method == 4) tol[1:4] <- 3e-3
  if (method == 5) tol[1:4] <- 2e-4
  for (w in 0:8) {
    if (w >= 7 && !is.finite(vals[w + 1])) next
    rl <- tol[w + 1]; ab <- tol[w + 1] * 1e-2
    if (w == 6 && method > 0) { rl <- 0.15; ab <- 3 }
    # the bounded PORT counts (function evaluations) follow R to a quarter
    if (w == 6 && method == 5) { rl <- 0.25; ab <- 4 }
    # nlm codes 1 (gradient), 2 (step) and 3 (the last line search failed) all mean it stopped on its tolerances: a last-bit besselK difference moves a run between them
    if (w == 5 && method == 4) ab <- 1
    cases[[length(cases) + 1]] <<- case("fs", c(seed, n, kind, sm, method, w, gen, us), vals[w + 1], rel = rl, abs = ab)
  }
}
set.seed(20262201)
for (rep in 1:6) {
  n <- sample(120:200, 1); sd0 <- sample(1:100000, 1)
  gen <- c(rnorm(1), runif(1, 0.5, 2), runif(1, 1, 3)); gen <- c(gen, runif(1, -0.6, 0.6) * gen[3])
  for (m in 0:3) addfs(sd0, n, 0, 0, m, gen)
  addfs(sd0, n, 1, 0, 0, gen); addfs(sd0, n, 1, 0, 3, gen)
  addfs(sd0, n, 2, 0, 0, gen); addfs(sd0, n, 2, 1, 0, gen); addfs(sd0, n, 2, 0, 3, gen)
  addfs(sd0, n, 0, 0, 4, gen); addfs(sd0, n, 1, 0, 4, gen); addfs(sd0, n, 2, 0, 4, gen)
  addfs(sd0, n, 0, 0, 5, gen); addfs(sd0, n, 1, 0, 5, gen); addfs(sd0, n, 2, 0, 5, gen)
}
addlm <- function(seed, n, method, ss, sm, b, gen) {
  i <- 1:n
  x1 <- seq(0, 1, length.out = n); x2 <- ((7 * i) %% 11) / 11
  set.seed(seed); e <- rhyperb(n, param = gen)
  y <- b[1] + b[2] * x1 + b[3] * x2 + e
  d <- data.frame(y = y, x1 = x1, x2 = x2)
  res <- tryCatch(suppressWarnings(hyperblm(y ~ x1 + x2, data = d, method = meths[method + 1], startMethod = smn[sm + 1], startStarts = svs[ss + 1])), error = function(e) NULL)
  if (is.null(res) || is.null(res$MLE) || !all(is.finite(res$coefficients)) || !is.finite(res$MLE)) return(invisible())
  vals <- c(as.numeric(res$coefficients), as.numeric(res$distributionParams), res$MLE, res$convergence, res$iterations, as.numeric(res$residsParamStart))
  tol <- c(rep(1e-5, 3), rep(1e-5, 4), 1e-7, 0, 0, rep(1e-8, 4))
  if (method == 1) tol[1:7] <- 2e-4
  if (method == 4) tol[1:7] <- 3e-3
  for (w in 0:13) {
    rl <- tol[w + 1]; ab <- tol[w + 1] * 1e-2
    if (w == 0 || (w == 3)) ab <- max(ab, 1e-6)
    if (w == 9 && method %in% c(1, 4)) { rl <- 0.2; ab <- 3 }
    cases[[length(cases) + 1]] <<- case("lm", c(seed, n, method, ss, sm, w, b, gen), vals[w + 1], rel = rl, abs = ab)
  }
}
set.seed(20262202)
for (rep in 1:5) {
  n <- sample(100:160, 1); sd0 <- sample(1:100000, 1)
  b <- c(rnorm(1), rnorm(1), rnorm(1))
  gen <- c(0, runif(1, 0.5, 1.5), runif(1, 1.5, 3)); gen <- c(gen, runif(1, -0.5, 0.5) * gen[3])
  addlm(sd0, n, 0, 0, 0, b, gen)
  if (rep <= 3) { addlm(sd0, n, 0, 2, 0, b, gen); addlm(sd0, n, 1, 0, 0, b, gen) }
  if (rep <= 3) addlm(sd0, n, 4, 0, 0, b, gen)
}
emit("ghypstand", "GeneralizedHyperbolic", list(cases))
