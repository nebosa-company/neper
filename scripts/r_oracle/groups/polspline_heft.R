# polspline heft (heftall.c): knots, logl, thetas, the log standard errors and the fitted hazard.
#   "heft" args: n, penalty (-1 default), nuser, user knots.., tails[5], shift, maxknots, mindist, x[n].., delta[n].., what, idx
#   what: 0 nk 1 knots[idx] 2 thetak[idx] 3 thetap[idx] 4 thetal[idx] 5 logse[idx] 6 logl[idx] 7 adddel[idx] 8 penalty 9 shift
#         10 hheft(x[idx])
#   tolerances: logl, knots, logse, penalty, shift 1e-9; thetas and the hazard 1e-7 (Newton stops at a logl change of 1e-7, and the
#   thetas of an ill-conditioned fit move by about 1e-8 relative with the last bits of the arithmetic)
suppressMessages(library(polspline))
cases <- list()
set.seed(20261124)
cens <- function(t, rate) { ct <- rexp(length(t), rate); list(x = pmin(t, ct), d = as.numeric(t <= ct)) }
c1 <- cens(rweibull(120, 1.5, 2), 0.2)
c2 <- cens(rgamma(110, 2), 0.15)
c3 <- cens(rlnorm(100), 0.1)
configs <- list(
  list(x = rexp(110), d = rep(1, 110)),
  list(x = c1$x, d = c1$d),
  list(x = c2$x, d = c2$d),
  list(x = c3$x, d = c3$d, leftlin = TRUE),
  list(x = rweibull(100, 2, 3), d = rep(1, 100), maxknots = 4),
  list(x = rgamma(110, 3), d = rep(1, 110), penalty = 2),
  list(x = rexp(100) + 0.1, d = rep(1, 100), knots = c(0.3, 0.8, 1.5, 2.5)),
  list(x = rweibull(100, 1.2, 2), d = rep(1, 100), mindist = 3),
  list(x = rlnorm(100, 0.5), d = rep(1, 100), rightlog = -0.5),
  list(x = rgamma(100, 2, 0.5), d = rep(1, 100), leftlog = -0.5),
  list(x = rexp(100), d = rep(1, 100), knots = c(0.2, 0.6, 1.2, 2)),
  list(x = rgamma(90, 2), d = rep(1, 90), maxknots = 5),
  list(x = rweibull(100, 1.3, 2), d = rep(1, 100), knots = c(0.5, 1, 1.8, 2.6, 3.5)),
  list(x = rexp(90), d = rep(1, 90), maxknots = 3),
  list(x = rweibull(90, 1.6, 2), d = rep(1, 90), knots = c(0.7, 1.4, 2.3))
)
nfit <- 0
for (cf in configs) {
  ox <- order(cf$x)
  x <- round(cf$x[ox], 3); d <- cf$d[ox]
  x[x <= 0] <- 0.001
  n <- length(x)
  args <- list(data = x, delta = d)
  for (nm in c("penalty", "knots", "leftlin", "leftlog", "rightlog", "maxknots", "mindist")) if (!is.null(cf[[nm]])) args[[nm]] <- cf[[nm]]
  f <- tryCatch(withCallingHandlers(do.call(heft, args), warning = function(w) stop(w)), error = function(e) { message("skipped: ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  # a fit that R itself changes under a 1e-13 relative nudge of the data is a numerical coin flip: skip it
  stable <- TRUE
  for (s in 1:3) {
    a2 <- args
    a2$data <- x * (1 + 1e-13 * sin(s * 7.3 * x))
    g <- tryCatch(suppressWarnings(do.call(heft, a2)), error = function(e) NULL)
    if (is.null(g) || length(g$knots) != length(f$knots) || !identical(as.numeric(g$adddel), as.numeric(f$adddel)) ||
        any(abs(g$thetak - f$thetak) > 1e-5 * (1 + abs(f$thetak)))) stable <- FALSE
  }
  if (!stable) { message("unstable fit skipped: n=", n); next }
  nfit <- nfit + 1
  tails <- c(0, 0, 0, 0, 1)
  if (!is.null(cf$leftlog)) { tails[1] <- 1; tails[2] <- cf$leftlog }
  if (!is.null(cf$rightlog)) { tails[3] <- 1; tails[4] <- cf$rightlog }
  if (!is.null(cf$leftlin) && cf$leftlin) tails[5] <- 0
  nuser <- length(cf$knots)
  pre <- c(n, if (is.null(cf$penalty)) -1 else cf$penalty, nuser, cf$knots, tails, f$shift,
           if (is.null(cf$maxknots)) 0 else cf$maxknots, if (is.null(cf$mindist)) 5 else cf$mindist, x, d)
  add <- function(what, idx, v, rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <<- case("heft", c(pre, what, idx), as.numeric(v), rel = rel, abs = abs)
  nk <- length(f$knots)
  add(0, 0, nk, 0, 0)
  for (i in 1:nk) { add(1, i - 1, f$knots[i]); add(2, i - 1, f$thetak[i], 1e-7, 1e-9); add(6, i - 1, f$logl[i]); add(7, i - 1, f$adddel[i], 0, 0) }
  for (i in 1:2) { add(3, i - 1, f$thetap[i], 1e-7, 1e-9); add(4, i - 1, f$thetal[i], 1e-7, 1e-9); add(5, i - 1, f$logse[i]) }
  add(8, 0, f$penalty); add(9, 0, f$shift)
  for (i in round(seq(2, n, length.out = 6))) add(10, i - 1, polspline:::hheft(x[i], f), 1e-7, 1e-12)
}
message("fits: ", nfit)
emit("polspline_heft", "polspline", list(cases))
