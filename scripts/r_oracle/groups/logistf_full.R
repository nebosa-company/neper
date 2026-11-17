# logistf in full: Firth fits with the package's own iteration, profile penalized likelihood limits, FLIC, FLAC, weights, offsets, controls,
# logistftest, anova, add1/drop1, forward/backward, predict, profile, logistf.pdf and PVR.confint, against the logistf R package.
#
# One case is one R call. The case args are a header, the problem and then R's answer; the fixture runs the same call and counts the
# numbers that differ (the case want is 0 mismatches). Header (0-based):
#   0 n, 1 k, 2 m (answer length), 3 mask (which parts of the answer), 4 firth, 5 pl, 6 intercept, 7 flic, 8 maxit, 9 maxstep, 10 maxhs,
#   11 lconv, 12 gconv, 13 xconv, 14 irls, 15 tau, 16 plmaxit, 17 plmaxstep, 18 plmaxhs, 19 pllconv, 20 plxconv, 21 alpha,
#   22 nplconf, 23 nterms, 24 hasW, 25 hasO, 26 ne
# then plconf (nplconf, 1-based), terms.fit (nterms, 1-based), y (n), x (n*k column-major), w (n), offset (n), extra (ne), answer (m).
# Answer parts by mask bit: 0 coef, 1 var, 2 prob ci.lower ci.upper, 3 loglik full null, 4 iter full null, 5 df n, 6 linear.predictors,
# 7 predict, 8 hat.diag, 9 pl.iter (k by 3 by rows), 10 pl.conv (rows of 4)
suppressMessages(library(logistf))
cases <- list()
nn <- function(v) as.numeric(v)

popt <- function(firth = TRUE, pl = TRUE, int = 1, flic = 0, control = logistf.control(), plcontrol = logistpl.control(), tau = 0.5, alpha = 0.05) {
  c(NA, NA, NA, NA, firth, pl, int, flic, control$maxit, control$maxstep, control$maxhs, control$lconv, control$gconv, control$xconv,
    as.numeric(control$fit == "IRLS"), tau, plcontrol$maxit, plcontrol$maxstep, plcontrol$maxhs, plcontrol$lconv, plcontrol$xconv, alpha)
}

pack <- function(kind, n, k, mask, o, y, x, w = NULL, off = NULL, plconf = NULL, terms = NULL, extra = numeric(), expected) {
  o[1:4] <- c(n, k, length(expected), mask)
  hdr <- c(o, length(plconf), length(terms), !is.null(w), !is.null(off), length(extra))
  expected <- nn(expected)
  cases[[length(cases) + 1]] <<- case(kind, c(hdr, plconf, terms, y, as.vector(x), w, off, extra, expected), 0, rel = 0, abs = 0)
}

flat <- function(f, mask, pl) {
  r <- numeric()
  if (bitwAnd(mask, 1)) r <- c(r, f$coefficients)
  if (bitwAnd(mask, 2)) r <- c(r, as.vector(as.matrix(f$var)))
  if (bitwAnd(mask, 4)) r <- c(r, f$prob, f$ci.lower, f$ci.upper)
  if (bitwAnd(mask, 8)) r <- c(r, f$loglik[["full"]], f$loglik[["null"]])
  if (bitwAnd(mask, 16)) r <- c(r, f$iter[["full"]], f$iter[["null"]])
  if (bitwAnd(mask, 32)) r <- c(r, f$df, f$n)
  if (bitwAnd(mask, 64)) r <- c(r, f$linear.predictors)
  if (bitwAnd(mask, 128)) r <- c(r, f$predict)
  if (bitwAnd(mask, 256)) r <- c(r, f$hat.diag)
  if (bitwAnd(mask, 512)) r <- c(r, as.vector(t(f$pl.iter)))
  if (bitwAnd(mask, 1024)) r <- c(r, as.vector(t(f$pl.conv)))
  nn(r)
}

quiet <- function(expr) withCallingHandlers(expr, warning = function(w) invokeRestart("muffleWarning"), message = function(m) invokeRestart("muffleMessage"))

# data sets: continuous and binary covariates, optionally separated
make <- function(n, k, kind = "plain") {
  X <- matrix(rnorm(n * k), n, k)
  if (k > 1) X[, 2] <- rbinom(n, 1, 0.4)
  b <- c(1.1, -1.4, 0.6, 0.3)[seq_len(k)]
  eta <- 0.2 + X %*% b
  y <- rbinom(n, 1, plogis(eta))
  if (kind == "sep") { y <- as.numeric(X[, 1] > 0.2); flip <- sample(n, 2); y[flip] <- 1 - y[flip] }
  if (kind == "perfect") y <- as.numeric(X[, 1] > 0.0)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k)))
  d$w <- sample(c(1, 2, 3, 0.5, 1.5), n, TRUE); d$o <- round(rnorm(n, 0, 0.4), 3)
  d
}

fml <- function(k) as.formula(paste("y ~", paste0("x", seq_len(k), collapse = " + ")))

fit_case <- function(d, k, kind = "fit", mask = 2^11 - 1, weights = FALSE, offset = FALSE, firth = TRUE, pl = TRUE, flic = FALSE, control = logistf.control(), plcontrol = logistpl.control(),
                     tau = 0.5, alpha = 0.05, plconf = NULL, terms = NULL, mf = NULL) {
  f <- fml(k); n <- nrow(d)
  x <- model.matrix(f, d)
  mc <- logistf.mod.control(tau = tau, terms.fit = terms)
  call_args <- list(formula = f, data = d, pl = pl, alpha = alpha, control = control, plcontrol = plcontrol, modcontrol = mc, firth = firth, flic = flic)
  if (!is.null(plconf)) call_args$plconf <- plconf
  if (weights) call_args$weights <- d$w
  if (offset) call_args$offset <- d$o
  fit <- tryCatch(quiet(do.call(logistf, call_args)), error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  if (!pl) mask <- bitwAnd(mask, bitwNot(512 + 1024))
  if (kind == "flic") {
    # flic(lfobject) on a logistf fit of the same model
    call_args$flic <- FALSE
    lf0 <- tryCatch(quiet(do.call(logistf, call_args)), error = function(e) NULL)
    if (is.null(lf0)) return(invisible())
    fit <- tryCatch(quiet(flic(lf0)), error = function(e) NULL)
    if (is.null(fit)) return(invisible())
    mask <- bitwAnd(mask, bitwNot(16 + 256 + 512 + 1024))
  }
  pack(kind, n, ncol(x), mask, popt(firth, pl, 1, flic, control, plcontrol, tau, alpha), d$y, x, if (weights) d$w, if (offset) d$o, plconf, terms, numeric(), flat(fit, mask, pl))
}

set.seed(20261301)
settings <- list()
# plain Firth, several sizes and separation
for (rep in 1:8) {
  k <- c(1, 2, 3, 4, 2, 3, 1, 2)[rep]; n <- c(30, 45, 60, 25, 50, 40, 35, 70)[rep]
  kind <- c("plain", "plain", "plain", "sep", "sep", "perfect", "plain", "plain")[rep]
  d <- make(n, k, kind)
  fit_case(d, k)
}
# the controls
d <- make(50, 3)
fit_case(d, 3, control = logistf.control(maxit = 5))
fit_case(d, 3, control = logistf.control(maxit = 3, maxstep = 0.5))
fit_case(d, 3, control = logistf.control(maxhs = 5))
fit_case(d, 3, control = logistf.control(maxhs = 3, lconv = 1e-8, gconv = 1e-8, xconv = 1e-8, maxit = 60))
fit_case(d, 3, control = logistf.control(fit = "IRLS"))
fit_case(d, 3, control = logistf.control(fit = "IRLS", maxit = 4))
fit_case(d, 3, control = logistf.control(maxstep = -1))
fit_case(d, 3, plcontrol = logistpl.control(maxit = 8))
fit_case(d, 3, plcontrol = logistpl.control(maxhs = 4, maxstep = 1))
fit_case(d, 3, plcontrol = logistpl.control(lconv = 1e-9, xconv = 1e-9, maxit = 200))
fit_case(d, 3, tau = 0.25)
fit_case(d, 3, tau = 1)
fit_case(d, 3, alpha = 0.1)
fit_case(d, 3, firth = FALSE)
fit_case(d, 3, pl = FALSE)
fit_case(d, 3, firth = FALSE, pl = FALSE)
fit_case(d, 3, plconf = c(3, 1))
fit_case(d, 3, plconf = 2)
fit_case(d, 3, terms = c(1, 3))
fit_case(d, 3, terms = c(1, 2, 3), plconf = c(2, 3))
fit_case(d, 3, terms = c(2, 3), pl = FALSE)
# weights and offsets
d <- make(55, 3)
fit_case(d, 3, weights = TRUE)
fit_case(d, 3, offset = TRUE)
fit_case(d, 3, weights = TRUE, offset = TRUE)
fit_case(d, 3, weights = TRUE, firth = FALSE)
fit_case(d, 3, weights = TRUE, control = logistf.control(fit = "IRLS"))
fit_case(d, 3, offset = TRUE, control = logistf.control(maxhs = 4))
dsep <- make(45, 2, "sep")
fit_case(dsep, 2, weights = TRUE, offset = TRUE)
# FLIC
for (rep in 1:4) {
  d <- make(c(40, 60, 35, 50)[rep], c(2, 3, 1, 3)[rep], c("plain", "sep", "plain", "plain")[rep])
  k <- c(2, 3, 1, 3)[rep]
  fit_case(d, k, flic = TRUE)
  fit_case(d, k, kind = "flic")
}
d <- make(50, 3)
fit_case(d, 3, flic = TRUE, pl = FALSE)
fit_case(d, 3, flic = TRUE, offset = TRUE)
fit_case(d, 3, kind = "flic", weights = TRUE)
fit_case(d, 3, kind = "flic", offset = TRUE)
fit_case(d, 3, kind = "flic", terms = c(1, 2))
# FLAC
flac_case <- function(d, k, pl = TRUE, weights = FALSE, offset = FALSE, control = logistf.control(), tau = 0.5, terms = NULL) {
  f <- fml(k); n <- nrow(d); x <- model.matrix(f, d)
  a <- list(formula = f, data = d, pl = pl, control = control, modcontrol = logistf.mod.control(tau = tau, terms.fit = terms))
  if (weights) a$weights <- d$w
  if (offset) a$offset <- d$o
  fit <- tryCatch(quiet(do.call(flac, a)), error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  mask <- 1 + 2 + 4 + 8 + 32 + 64 + 128
  pack("flac", n, ncol(x), mask, popt(TRUE, pl, 1, 0, control, logistpl.control(), tau), d$y, x, if (weights) d$w, if (offset) d$o, NULL, terms, numeric(), flat(fit, mask, pl))
}
for (rep in 1:4) {
  d <- make(c(40, 55, 35, 50)[rep], c(2, 3, 1, 3)[rep], c("plain", "sep", "plain", "plain")[rep])
  flac_case(d, c(2, 3, 1, 3)[rep])
}
d <- make(45, 3)
flac_case(d, 3, pl = FALSE)
flac_case(d, 3, weights = TRUE)
flac_case(d, 3, offset = TRUE)
flac_case(d, 3, tau = 0.3)
flac_case(d, 3, control = logistf.control(maxit = 6, maxstep = 1))

#@@PARTS@@
emit("logistf_full", "logistf", list(cases))
