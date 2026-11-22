# polspline logspline fitting (nlsd.c): knots, coefficients, penalty, mind, the AIC table and the fitted density.
#   "lsfit" args: n, maxknots, nknots_arg (R's -nknots, or the number of user knots), lower, lbound, upper, ubound, penalty (-1 default),
#   mind (-1 default), nuser, user knots.., x[n].., what, idx
#   what: 0 nknots 1 coef.pol[idx] 2 coef.kts[idx] 3 knots[idx] 4 penalty 5 mind 6 table rows 7 table ad[idx] 8 table logl[idx]
#         9 table label[idx] 10 dlogspline(x[idx], fit)
suppressMessages(library(polspline))
cases <- list()
set.seed(20261123)
configs <- list(
  list(x = rnorm(120)),
  list(x = rexp(150), lbound = 0),
  list(x = c(rnorm(80), rnorm(80, 4))),
  list(x = rnorm(100), lbound = -4, ubound = 4),
  list(x = rgamma(150, 3), lbound = 0, maxknots = 6),
  list(x = rnorm(130), knots = c(-1.5, -0.5, 0.5, 1.5)),
  list(x = rnorm(110), nknots = 5),
  list(x = rt(160, 4), penalty = 2.5),
  list(x = round(rnorm(140), 1)),
  list(x = rexp(100), lbound = 0, ubound = 12),
  list(x = rweibull(200, 1.5), mind = 4),
  list(x = rnorm(180) * 2 + 1),
  list(x = rlnorm(120), lbound = 0),
  list(x = rnorm(90), lbound = -5, ubound = 5),
  list(x = rnorm(90), nknots = 6),
  list(x = rexp(90), ubound = 15),
  list(x = rnorm(90), lbound = -5, ubound = 5, maxknots = 5)
)
nfit <- 0
for (cf in configs) {
  x <- sort(round(cf$x, 5))
  n <- length(x)
  args <- list(x = x)
  for (nm in c("lbound", "ubound", "maxknots", "knots", "nknots", "penalty", "mind")) if (!is.null(cf[[nm]])) args[[nm]] <- cf[[nm]]
  args$error.action <- 0
  f <- tryCatch(withCallingHandlers(do.call(logspline, args), warning = function(w) stop(w)), error = function(e) { message("skipped: ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  # a fit that R itself changes under a 1e-13 relative nudge of the data is a numerical coin flip: skip it
  stable <- TRUE
  for (s in 1:4) {
    a2 <- args
    a2$x <- sort(x * (1 + 1e-13 * sin(s * 7.3 * x)))
    if (!is.null(a2$knots)) a2$knots <- a2$knots
    g <- tryCatch(suppressWarnings(do.call(logspline, a2)), error = function(e) NULL)
    if (is.null(g) || g$nknots != f$nknots || !identical(as.numeric(g$logl[, 2]), as.numeric(f$logl[, 2])) || any(abs(g$coef.pol - f$coef.pol) > 1e-6 * abs(f$coef.pol))) stable <- FALSE
  }
  if (!stable) { message("unstable fit skipped: n=", n); next }
  nfit <- nfit + 1
  nuser <- length(cf$knots)
  pre <- c(n, if (is.null(cf$maxknots)) 0 else cf$maxknots,
           if (!is.null(cf$knots)) length(cf$knots) else if (is.null(cf$nknots)) 0 else -cf$nknots,
           as.numeric(!is.null(cf$lbound)), if (is.null(cf$lbound)) 0 else cf$lbound,
           as.numeric(!is.null(cf$ubound)), if (is.null(cf$ubound)) 0 else cf$ubound,
           if (is.null(cf$penalty)) -1 else cf$penalty, if (is.null(cf$mind)) -1 else cf$mind,
           nuser, cf$knots, x)
  add <- function(what, idx, v, rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <<- case("lsfit", c(pre, what, idx), as.numeric(v), rel = rel, abs = abs)
  add(0, 0, f$nknots, 0, 0)
  for (i in 1:2) add(1, i - 1, f$coef.pol[i])
  for (i in seq_along(f$knots)) { add(2, i - 1, f$coef.kts[i]); add(3, i - 1, f$knots[i]) }
  add(4, 0, f$penalty); add(5, 0, f$mind, 0, 0)
  lg <- f$logl
  add(6, 0, nrow(lg), 0, 0)
  for (r in seq_len(nrow(lg))) { add(7, r - 1, lg[r, 2], 0, 0); add(8, r - 1, lg[r, 3]); add(9, r - 1, lg[r, 1], 0, 0) }
  for (i in round(seq(1, n, length.out = 7))) add(10, i - 1, dlogspline(x[i], f), rel = 1e-8)  # NR stops at a 1e-6 relative step: tail densities agree to ~1e-8
}
message("fits: ", nfit)
emit("polspline_logfit", "polspline", list(cases))
