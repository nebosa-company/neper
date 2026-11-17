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
# ---- tests, selection, predict, profile, pdf, PVR on a design with an interaction
make2 <- function(n, kind = "plain") {
  d <- data.frame(x1 = rnorm(n), x2 = rbinom(n, 1, 0.45), x3 = rnorm(n), x4 = rnorm(n))
  eta <- 0.1 + 1.3 * d$x1 - 0.9 * d$x2 + (kind != "null") * 0.7 * d$x3 + 0.5 * d$x1 * d$x2
  d$y <- rbinom(n, 1, plogis(eta))
  d$w <- sample(c(1, 2, 3, 0.5, 1.5), n, TRUE); d$o <- round(rnorm(n, 0, 0.4), 3)
  d
}
FULL <- y ~ x1 + x2 + x3 + x4 + x1:x2
cname <- function(d) colnames(model.matrix(FULL, d))
fm_cols <- function(d, cols) { cn <- cname(d)[cols]; nt <- cn[cn != "(Intercept)"]; as.formula(paste("y ~", if (length(nt)) paste(nt, collapse = " + ") else "1")) }
fitm <- function(d, cols, pl = TRUE, firth = TRUE, weights = FALSE, offset = FALSE, control = logistf.control(), plcontrol = logistpl.control(), tau = 0.5, alpha = 0.05, flic = FALSE) {
  a <- list(formula = fm_cols(d, cols), data = d, pl = pl, firth = firth, control = control, plcontrol = plcontrol, modcontrol = logistf.mod.control(tau = tau), alpha = alpha, flic = flic)
  if (weights) a$weights <- d$w
  if (offset) a$offset <- d$o
  quiet(do.call(logistf, a))
}
place <- function(v, nm, cn) { r <- numeric(length(cn)); r[match(nm, cn)] <- v; r }
facs_of <- function(d) {
  cn <- cname(d); f <- attr(terms(FULL), "factors")[-1, , drop = FALSE]
  m <- matrix(0, nrow(f), length(cn)); m[, match(colnames(f), cn)] <- f; m
}
pack2 <- function(kind, d, o, extra, expected, weights = FALSE, offset = FALSE) {
  x <- model.matrix(FULL, d)
  pack(kind, nrow(d), ncol(x), 0, o, d$y, x, if (weights) d$w, if (offset) d$o, NULL, NULL, extra, expected)
}
sel_answer <- function(f, d, order) {
  cn <- cname(d); K <- length(cn); nm <- names(f$coefficients)
  v <- matrix(0, K, K); idx <- match(nm, cn); v[idx, idx] <- as.matrix(f$var)
  c(place(f$coefficients, nm, cn), as.vector(v), place(f$prob, nm, cn), place(f$ci.lower, nm, cn), place(f$ci.upper, nm, cn),
    f$loglik[["full"]], f$loglik[["null"]], f$df, length(order), match(order, cn))
}

# logistftest
for (rep in 1:7) {
  d <- make2(c(40, 55, 45, 60, 50, 35, 70)[rep]); cols <- list(1:4, 1:5, 1:6, c(1, 2, 3), c(1, 2, 4, 6), 1:3, 1:6)[[rep]]
  fw <- rep %in% c(3, 6); fo <- rep %in% c(4, 6); firth <- rep != 5
  f <- fitm(d, cols, pl = FALSE, firth = firth, weights = fw, offset = fo)
  K <- length(cols)
  tst <- list(2:K, c(2, 3), K, 2:3, 1:K, c(3, 2), 2)[[rep]]
  vals <- NULL; b0 <- NULL
  if (rep == 2) vals <- c(0.4, -0.2)
  if (rep == 7) b0 <- c(0, 0.3, 0.1, 0, 0, 0)[seq_len(K)]
  call_args <- list(f, test = tst, firth = firth)
  if (!is.null(vals)) call_args$values <- vals
  if (!is.null(b0)) call_args$beta0 <- b0
  r <- tryCatch(quiet(do.call(logistftest, call_args)), error = function(e) NULL)
  if (is.null(r)) next
  ex <- c(length(cols), cols, length(tst), tst, length(vals), vals, length(b0), b0)
  pack2("test", d, popt(firth, FALSE), ex, c(r$loglik[["full"]], r$loglik[["null"]], r$df, r$prob), fw, fo)
}
# anova: nested models, PLR, and a formula
for (rep in 1:6) {
  d <- make2(c(50, 60, 45, 55, 40, 65)[rep])
  fw <- rep == 3; fo <- rep == 4
  big <- list(1:5, 1:6, 1:4, 1:5, 1:6, 1:5)[[rep]]; small <- list(c(1, 2, 3), c(1, 2, 3, 4), c(1, 2), c(1, 2, 3, 5), c(1, 2, 4), c(1, 3, 4))[[rep]]
  fb <- fitm(d, big, pl = FALSE, weights = fw, offset = fo); fs <- fitm(d, small, pl = FALSE, weights = fw, offset = fo)
  r <- tryCatch(quiet(anova(fb, fs)), error = function(e) NULL)
  if (!is.null(r)) pack2("anova_n", d, popt(TRUE, FALSE), c(length(big), big, length(small), small, nrow(facs_of(d)), as.vector(facs_of(d))), c(r$chisq, r$df, r$pval, r$PLR1, r$PLR2), fw, fo)
  r <- tryCatch(quiet(anova(fb, fs, method = "PLR")), error = function(e) NULL)
  if (!is.null(r)) pack2("anova_p", d, popt(TRUE, FALSE), c(length(big), big, length(small), small), c(r$chisq, r$df, r$pval, r$PLR1, r$PLR2), fw, fo)
  cn <- cname(d)
  dr <- setdiff(big, small)[1]
  r <- tryCatch(quiet(anova(fb, formula = as.formula(paste("~", cn[dr])), method = "nested")), error = function(e) NULL)
  if (!is.null(r)) pack2("anova_f", d, popt(TRUE, FALSE), c(length(big), big, 1, dr, nrow(facs_of(d)), as.vector(facs_of(d))), c(r$chisq, r$df, r$pval, r$PLR1, r$PLR2), fw, fo)
}
# add1 and drop1
for (rep in 1:4) {
  d <- make2(c(55, 70, 45, 60)[rep]); fw <- rep == 2; fo <- rep == 3
  cols <- list(1:3, c(1, 2, 3), c(1, 2), 1:4)[[rep]]; cn <- cname(d)
  f <- fitm(d, cols, pl = FALSE, weights = fw, offset = fo)
  sc <- setdiff(2:6, cols)
  m <- quiet(add1(f, scope = cn[sc], data = d))
  pack2("add1", d, popt(TRUE, FALSE), c(length(cols), cols, length(sc), sc), as.vector(t(m)), fw, fo)
  m <- quiet(drop1(f, data = d))
  pack2("drop1", d, popt(TRUE, FALSE), c(length(cols), cols, length(cols) - 1, cols[-1], 0), as.vector(t(m)), fw, fo)
}
# forward (R cannot select among interaction terms: data[, scope])
FULL <- y ~ x1 + x2 + x3 + x4
for (rep in 1:8) {
  d <- make2(c(80, 100, 70, 90, 120, 85, 95, 110)[rep]); fw <- rep == 3; fo <- rep == 6; cn <- cname(d)
  start <- c(1, 2)
  f <- fitm(d, start, pl = TRUE, weights = fw, offset = fo)
  sc <- 3:5; slentry <- c(0.05, 0.2, 0.05, 0.5, 0.1, 0.05, 0.3, 0.05)[rep]; pl <- rep %% 2 == 0; steps <- c(1000, 1000, 1000, 2, 1000, 1000, 1000, 1000)[rep]
  lg <- capture.output(r <- tryCatch(quiet(forward(f, scope = cn[sc], data = d, steps = steps, slentry = slentry, trace = TRUE, pl = pl)), error = function(e) { message("ERR ", conditionMessage(e)); NULL }))
  if (is.null(r)) next
  ord <- sub("^.*added +([^ ]+) .*$", "\\1", grep("added", lg, value = TRUE))
  pack2("forward", d, popt(TRUE, TRUE), c(length(start), start, length(sc), sc, steps, slentry, pl), sel_answer(r, d, ord), fw, fo)
}
# backward, with an interaction, and with the full penalty on main effects
for (rep in 1:8) {
  fp <- rep %in% c(7, 8)
  FULL <- y ~ x1 + x2 + x3 + x4
  d <- make2(c(90, 110, 80, 100, 120, 95, 105, 130)[rep], if (rep %in% c(2, 5)) "null" else "plain"); fw <- rep == 3; fo <- rep == 6
  cols <- seq_along(cname(d))
  f <- fitm(d, cols, pl = TRUE, weights = fw, offset = fo)
  slstay <- c(0.05, 0.2, 0.05, 0.5, 0.1, 0.05, 0.3, 0.05)[rep]; steps <- c(1000, 1000, 1000, 2, 1000, 1000, 1000, 1000)[rep]
  lg <- capture.output(r <- tryCatch(quiet(backward(f, data = d, steps = steps, slstay = slstay, trace = TRUE, full.penalty = fp)), error = function(e) { message("ERR ", conditionMessage(e)); NULL }))
  if (is.null(r)) next
  ord <- sub("^.*removed +([^ ]+) .*$", "\\1", grep("removed", lg, value = TRUE))
  fa <- facs_of(d)
  pack2("backward", d, popt(TRUE, TRUE), c(length(cols), cols, nrow(fa), as.vector(fa), steps, slstay, fp), sel_answer(r, d, ord), fw, fo)
}
FULL <- y ~ x1 + x2 + x3 + x4 + x1:x2
# ---- predict, profile, logistf.pdf, logistpl, PVR.confint, summary and extractAIC numbers, a start value
FULL <- y ~ x1 + x2 + x3
d3fit <- function(d, kind, firth = TRUE, weights = FALSE, offset = FALSE, flic = FALSE) {
  a <- list(formula = FULL, data = d, pl = FALSE, firth = firth, flic = flic)
  if (weights) a$weights <- d$w
  if (offset) a$offset <- d$o
  if (kind == 2) return(quiet(do.call(flac, a[names(a) != "firth" & names(a) != "flic"])))
  f <- quiet(do.call(logistf, a))
  if (kind == 1) f <- quiet(flic(f))
  f
}
pred_answer <- function(p, type, se) {
  if (type == "link") { if (se) c(p$fit, p$se.fit) else as.numeric(p) }
  else if (type == "response") { if (se) c(p$fit, p$lower, p$upper) else as.numeric(p) }
  else { if (se) c(as.vector(p$fit), as.vector(p$se.fit), attr(p$fit, "constant")) else c(as.vector(p), attr(p, "constant")) }
}
npred <- 0
for (rep in 1:30) {
  n <- sample(40:70, 1); d <- make2(n); fw <- rep %% 5 == 3; fo <- rep %% 7 == 4
  obj <- (rep - 1) %% 3
  type <- c("link", "response", "terms")[((rep - 1) %/% 3) %% 3 + 1]
  se <- rep %% 2 == 0; fl <- obj == 0 && rep %% 4 == 1; has_new <- rep %% 3 != 1
  f <- d3fit(d, obj, weights = fw, offset = fo)
  x <- model.matrix(FULL, d); k <- ncol(x)
  m <- 6; nd <- data.frame(x1 = round(rnorm(m), 2), x2 = rbinom(m, 1, 0.4), x3 = round(rnorm(m), 2))
  nx <- model.matrix(~ x1 + x2 + x3, nd)
  args <- list(f, type = type, se.fit = se)
  if (has_new) args$newdata <- nd
  if (obj == 0) args$flic <- fl
  ref <- NULL
  if (type == "terms" && se) { ref <- c(x1 = 0, x2 = 0, x3 = 0); args$reference <- ref }
  p <- tryCatch(quiet(do.call(predict, args)), error = function(e) { message("ERR ", conditionMessage(e)); NULL })
  if (is.null(p)) next
  assign <- attr(x, "assign")
  refx <- if (is.null(ref)) numeric() else c(1, ref)
  ex <- c(obj, match(type, c("link", "response", "terms")) - 1, se, fl, has_new, m, if (has_new) as.vector(nx), max(assign), assign, length(refx), refx)
  pack("predict", n, k, 0, popt(TRUE, FALSE), d$y, x, if (fw) d$w, if (fo) d$o, NULL, NULL, ex, pred_answer(p, type, se))
}
# profile
for (rep in 1:5) {
  d <- make2(c(40, 55, 70, 50, 60)[rep]); k <- 3
  f <- quiet(logistf(FULL, d, pl = FALSE))
  x <- model.matrix(FULL, d); pos <- c(2, 3, 4, 2, 3)[rep]; steps <- c(30, 50, 40, 25, 100)[rep]; pitch <- c(0.05, 0.1, 0.05, 0.2, 0.05)[rep]
  lim <- if (rep == 4) c(-1, 2) else NULL
  alpha <- c(0.05, 0.05, 0.1, 0.05, 0.05)[rep]
  a <- list(f, variable = colnames(x)[pos], steps = steps, pitch = pitch, alpha = alpha)
  if (!is.null(lim)) a$limits <- lim
  r <- tryCatch(quiet(do.call(profile, a)), error = function(e) { message("ERR ", conditionMessage(e)); NULL })
  if (is.null(r)) next
  nk <- length(r$beta)
  ex <- c(pos, steps, pitch, !is.null(lim), if (is.null(lim)) c(0, 0) else lim, alpha)
  pack("profile", nrow(d), ncol(x), 0, popt(TRUE, FALSE), d$y, x, NULL, NULL, NULL, NULL, ex, c(nk, r$beta, r$stdbeta, r$profile, r$loglik, r$signed.root, r$cdf))
}
# logistf.pdf and logistpl, from fitted coefficients
for (rep in 1:8) {
  d <- make2(c(40, 55, 70, 50, 60, 45, 52, 66)[rep]); fw <- rep %% 3 == 0; fo <- rep %% 4 == 0; firth <- rep != 5
  f <- d3fit(d, 0, firth = firth, weights = fw, offset = fo)
  x <- model.matrix(FULL, d); y <- d$y; k <- ncol(x); n <- nrow(d)
  w <- if (fw) d$w else rep(1, n); o <- if (fo) d$o else rep(0, n)
  pos <- c(2, 3, 4, 2, 3, 4, 2, 3)[rep]; b <- f$coefficients[pos] + c(0.3, -0.5, 0.8, -0.2, 0.4, -0.7, 0.1, 0.6)[rep]
  r <- tryCatch(quiet(logistf:::logistf.pdf(x, y, pos = pos, firth = firth, weight = w, control = logistf.control(), offset = o, b = b, beta = f$coefficients, loglik = f$loglik[["full"]])), error = function(e) NULL)
  if (!is.null(r)) pack("pdf", n, k, 0, popt(firth, FALSE), y, x, if (fw) w, if (fo) o, NULL, NULL, c(pos, b, f$coefficients, f$loglik[["full"]]), c(r$chisq, r$pdf))
  ll0 <- f$loglik[["full"]] - qchisq(0.95, 1) / 2
  for (side in c(-1, 1)) {
    pc <- if (rep %% 2 == 0) logistpl.control(maxit = 12, maxhs = 3, maxstep = 1) else logistpl.control()
    r <- tryCatch(quiet(logistf:::logistpl(x, y, init = f$coefficients, i = pos, LL.0 = ll0, firth = firth, which = side, offset = o, weight = w, plcontrol = pc, modcontrol = logistf.mod.control())), error = function(e) NULL)
    if (is.null(r)) next
    pack("pl", n, k, 0, popt(firth, FALSE, plcontrol = pc), y, x, if (fw) w, if (fo) o, NULL, NULL, c(pos, side, ll0, f$coefficients), c(r$beta, r$loglik, r$iter, r$conv, as.vector(r$betahist)))
  }
}
# PVR.confint on several fits of one model
for (rep in 1:4) {
  nimp <- c(5, 8, 4, 6)[rep]; fits <- list(); skew <- rep %% 2 == 0; k <- c(3, 2, 4, 3)[rep]
  ok <- 0
  for (i in 1:nimp) { d <- make2(60); f <- quiet(logistf(as.formula(paste("y ~", paste0("x", seq_len(k - 1), collapse = " + "))), d)); fits[[i]] <- f }
  cm <- t(sapply(fits, function(f) f$coefficients)); lo <- t(sapply(fits, function(f) f$ci.lower)); up <- t(sapply(fits, function(f) f$ci.upper))
  r <- quiet(PVR.confint(fits, skewbeta = skew))
  za <- qnorm(1 - 0.05 / 2)
  pack("pvr", 0, k, 0, popt(TRUE, TRUE), numeric(), matrix(numeric(), 0, 0), NULL, NULL, NULL, NULL, c(nimp, k, as.vector(cm), as.vector(lo), as.vector(up), za, skew),
       c(r$estimate, r$ci[, 1], r$ci[, 2], r$lower.var, r$upper.var))
}
# summary and extractAIC numbers
for (rep in 1:5) {
  d <- make2(c(40, 55, 70, 50, 60)[rep]); fw <- rep == 3; fo <- rep == 4
  f <- d3fit(d, 0, weights = fw, offset = fo); fp <- quiet(logistf(FULL, d, weights = if (fw) d$w, offset = if (fo) d$o))
  x <- model.matrix(FULL, d); k <- ncol(x)
  cov <- fp$var; coefs <- fp$coefficients
  chi2 <- qchisq(1 - fp$prob, 1); LL <- -2 * (fp$loglik[["null"]] - fp$loglik[["full"]])
  wz <- tryCatch(t(coefs) %*% solve(cov) %*% coefs, error = function(e) NA)
  kp <- c(2, log(nrow(d)), 3, 2, 2)[rep]; ai <- extractAIC(fp, k = kp)
  pack("summary", nrow(d), k, 0, popt(TRUE, TRUE), d$y, x, if (fw) d$w, if (fo) d$o, NULL, NULL, kp,
       c(chi2, LL, 1 - pchisq(LL, fp$df), wz, 1 - pchisq(wz, fp$df), ai))
}
# a start value
d <- make2(60); x <- model.matrix(FULL, d)
for (rep in 1:3) {
  init <- list(c(0.1, 0.5, -0.5, 0.2), c(-1, 1, 1, 0), c(0, 0, 0, 3))[[rep]]
  f <- tryCatch(quiet(logistf(FULL, d, init = init, control = logistf.control(maxit = c(25, 4, 40)[rep]))), error = function(e) NULL)
  if (is.null(f)) next
  mask <- 1 + 2 + 4 + 8 + 16 + 32 + 64 + 128 + 256 + 512 + 1024
  pack("fit_init", nrow(d), ncol(x), mask, popt(TRUE, TRUE, control = logistf.control(maxit = c(25, 4, 40)[rep])), d$y, x, NULL, NULL, NULL, NULL, init, flat(f, mask, TRUE))
}
FULL <- y ~ x1 + x2 + x3 + x4 + x1:x2
emit("logistf_full", "logistf", list(cases))
