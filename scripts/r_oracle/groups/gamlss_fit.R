# gamlss fitting: the RS, CG and mixed algorithms on design-matrix models (no smoothers), families 0 NO 1 GA 2 PO 3 WEI 4 BCCG.
# A scenario opens with a case whose args are the 20-number header followed by the data; the cases after it carry the header with fam 99 and read the same fit.
# header: fam, algo (0 RS 1 CG 2 mixed), n, p0, p1, p2 (design columns), link kinds of mu, sigma, nu (4 identity, 5 log), out kind, out index, c.crit, n.cyc,
#         mixed n1, n2, autostep, centile p, mu.step, sigma.step, nu.step; data: y (n), w (n), X0 (n * p0), X1 (n * p1), X2 (n * p2), column-major
# out kinds: 0 coefficient (index into mu, sigma, nu coefficients one after the other), 1 G.deviance, 2 iter, 3 converged, 4 fitted parameter (k * n + i),
#            5 df.fit, 6 aic, 7 sbc, 8 working variable (k * n + i), 9 working weight, 10 linear predictor, 11 quantile residual i, 12 centile of observation i
suppressMessages(library(gamlss))
cases <- list()
famobj <- list(NO, GA, PO, WEI, BCCG)
mk <- function(fam, algo, y, w, Xs, links, steps, cc, ncyc, n1, n2, auto, formulas, rel = 1e-10) {
  n <- length(y)
  d <- data.frame(y = y, x1 = Xs$x1, x2 = Xs$x2, w = w)
  ctl <- gamlss.control(trace = FALSE, c.crit = cc, n.cyc = ncyc, mu.step = steps[1], sigma.step = steps[2], nu.step = steps[3], autostep = auto)
  fa <- famobj[[fam + 1]]
  lk <- c("identity", "log")[links - 3]
  fo <- do.call(fa, as.list(lk[seq_len(c(2, 2, 1, 2, 3)[fam + 1])]))
  method <- if (algo == 0) quote(RS()) else if (algo == 1) quote(CG()) else bquote(mixed(.(n1), .(n2)))
  args <- list(formula = as.formula(formulas[1]), family = fo, data = d, weights = d$w, method = method, control = ctl, trace = FALSE)
  if (length(formulas) > 1) args$sigma.formula <- as.formula(formulas[2])
  if (length(formulas) > 2) args$nu.formula <- as.formula(formulas[3])
  m <- tryCatch(suppressWarnings(do.call(gamlss, args)), error = function(e) NULL)
  if (is.null(m)) { message("SKIP fam ", fam, " algo ", algo, " ", paste(formulas, collapse = " | ")); return(invisible()) }
  np <- c(2, 2, 1, 2, 3)[fam + 1]
  X <- list(model.matrix(as.formula(formulas[1]), d), if (np > 1) model.matrix(as.formula(sub("^y", "", paste0("~", sub("^.*~", "", formulas[2])))), d), if (np > 2) model.matrix(as.formula(paste0("~", sub("^.*~", "", formulas[3]))), d))
  p <- c(ncol(X[[1]]), if (np > 1) ncol(X[[2]]) else 0, if (np > 2) ncol(X[[3]]) else 0)
  lks <- c(links, 4)[1:3]
  hdr <- function(f, kind, idx, pc = 0) c(f, algo, n, p, lks, kind, idx, cc, ncyc, n1, n2, as.numeric(auto), pc, steps)
  data <- c(y, w, unlist(lapply(X, as.vector)))
  par <- list(m$mu.fv, if (np > 1) m$sigma.fv, if (np > 2) m$nu.fv)
  first <- TRUE
  add <- function(kind, idx, want, pc = 0, r = rel) {
    h <- hdr(if (first) fam else 99, kind, idx, pc)
    cases[[length(cases) + 1]] <<- case("fit", if (first) c(h, data) else h, want, rel = r, abs = if (r == 0) 0 else 1e-12)
    first <<- FALSE
  }
  co <- c(coef(m, "mu"), if (np > 1) coef(m, "sigma"), if (np > 2) coef(m, "nu"))
  for (j in seq_along(co)) add(0, j - 1, unname(co[j]))
  add(1, 0, m$G.deviance)
  add(2, 0, m$iter, r = 0)
  add(3, 0, as.numeric(m$converged), r = 0)
  add(5, 0, m$df.fit, r = 0)
  add(6, 0, m$aic)
  add(7, 0, m$sbc)
  for (k in seq_len(np)) for (i in c(1, n %/% 2, n)) {
    add(4, (k - 1) * n + i - 1, par[[k]][i])
    nm <- c("mu", "sigma", "nu")[k]
    add(8, (k - 1) * n + i - 1, m[[paste0(nm, ".wv")]][i])
    add(9, (k - 1) * n + i - 1, m[[paste0(nm, ".wt")]][i])
    add(10, (k - 1) * n + i - 1, m[[paste0(nm, ".lp")]][i])
  }
  if (fam != 2) for (i in c(1, n %/% 2, n)) add(11, i - 1, resid(m)[c(0, cumsum(w))[i] + 1])
  for (pc in c(0.05, 0.5, 0.95)) for (i in c(1, n)) {
    q <- switch(fam + 1, qNO(pc, par[[1]][i], par[[2]][i]), qGA(pc, par[[1]][i], par[[2]][i]), qPO(pc, par[[1]][i]), qWEI(pc, par[[1]][i], par[[2]][i]), qBCCG(pc, par[[1]][i], par[[2]][i], par[[3]][i]))
    add(12, i - 1, q, pc)
  }
}
n <- 40
set.seed(20261501)
x1 <- round(runif(n, 0, 5), 3); x2 <- round(rnorm(n), 3)
XX <- list(x1 = x1, x2 = x2)
one <- rep(1, n)
yno <- round(2 + 0.7 * x1 - 0.5 * x2 + exp(-0.5 + 0.2 * x1) * rnorm(n), 4)
for (a in 0:2) mk(0, a, yno, one, XX, c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1 + x2", "y ~ x1"))
wts <- sample(1:3, n, TRUE)
mk(0, 0, yno, wts, XX, c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1", "y ~ x2"))
mk(0, 1, yno, wts, XX, c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1", "y ~ x2"))
mk(0, 0, yno, one, XX, c(4, 5, 4), c(0.8, 0.9, 1), 0.00001, 30, 1, 20, TRUE, c("y ~ x1 + x2", "y ~ x1"))
mk(0, 0, yno, one, XX, c(4, 5, 4), c(1, 1, 1), 0.001, 3, 1, 20, FALSE, c("y ~ x1", "y ~ 1"))
yga <- round(rgamma(n, shape = 4, scale = exp(0.5 + 0.2 * x1) / 4) + 0.01, 4)
for (a in 0:2) mk(1, a, yga, one, XX, c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1", "y ~ x2"))
mk(1, 1, yga, wts, XX, c(5, 5, 4), c(1, 1, 1), 0.00001, 30, 1, 20, TRUE, c("y ~ x1 + x2", "y ~ x1"))
ypo <- rpois(n, exp(0.3 + 0.25 * x1 - 0.2 * x2))
for (a in 0:2) mk(2, a, ypo, one, XX, c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1 + x2"))
ywe <- round(rweibull(n, shape = 2.2, scale = exp(0.8 + 0.1 * x1)), 4)
for (a in 0:2) mk(3, a, ywe, one, XX, c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1", "y ~ 1"))
mk(3, 1, ywe, one, XX, c(5, 5, 4), c(1, 1, 1), 0.00001, 40, 1, 20, TRUE, c("y ~ x1 + x2", "y ~ x1"))
ybc <- round(exp(1 + 0.15 * x1 + 0.2 * rnorm(n)), 4)
for (a in 0:2) mk(4, a, ybc, one, XX, c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, c("y ~ x1", "y ~ 1", "y ~ 1"))
mk(4, 1, ybc, one, XX, c(5, 5, 4), c(1, 1, 1), 0.00001, 40, 1, 20, TRUE, c("y ~ x1 + x2", "y ~ x1", "y ~ 1"))
emit("gamlss_fit", c("gamlss", "gamlss.dist"), list(cases))
