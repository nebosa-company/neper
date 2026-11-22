# polspline oldlogspline (lsdall.c): the censored-data log-spline fit, and doldlogspline/poldlogspline/qoldlogspline.
#   "olfit" args: nu, nr, nl, nint, hasl, lbound, hasu, ubound, nknots (-1 missing), nuser, penalty (-1 default), delete,
#   user knots.., uncensored[nu].., right[nr].., left[nl].., interval lo,hi pairs[2 nint].., what, x
#   what: 0 nk 1 coef[x] 2 knots[x] 3 bound[x] 4 length(logl) 5 logl[x] 6 penalty 7 sample 8 doldlogspline(x)
#         9 poldlogspline(x) 10 qoldlogspline(x)
suppressMessages(library(polspline))
cases <- list()
set.seed(20261124)
quiet <- function(expr) { out <- NULL; capture.output(out <- withCallingHandlers(expr, warning = function(w) stop(w))); out }
configs <- list(
  list(unc = rnorm(90)),
  list(unc = rexp(80), lbound = 0),
  list(unc = c(rnorm(50), rnorm(50, 4))),
  list(unc = rnorm(70), lbound = -4, ubound = 4),
  list(unc = rnorm(70), right = rnorm(20) + 0.8),
  list(unc = rnorm(70), left = rnorm(20) - 0.8),
  list(unc = rnorm(40), int = { m <- rnorm(30); cbind(round(m) - 0.5, round(m) + 0.5) }),
  list(unc = rnorm(60), right = rnorm(15) + 1, left = rnorm(15) - 1, int = { m <- rnorm(15); cbind(m - 0.3, m + 0.4) }),
  list(unc = rnorm(80), nknots = 5, delete = FALSE),
  list(unc = rnorm(80), knots = c(-3.5, -1.5, 0, 1.5, 3.5)),
  list(unc = rnorm(80), delete = FALSE),
  list(unc = rt(90, 5), penalty = 2.5),
  list(unc = round(rnorm(90), 1)),
  list(unc = rexp(70), right = rexp(20) + 1, lbound = 0)
)
# the package's C code writes 50 doubles into the (length(knots) + 4)-long coefficient vector it is given when the knots
# are the user's: a heap overrun in R itself. Such fits run in a child process that saves its answer and may die at exit.
fitit <- function(cf, nudge = 0, s = 0) {
  if (is.null(cf$knots)) return(fitit_here(cf, nudge, s))
  f1 <- tempfile(fileext = ".rds"); f2 <- tempfile(fileext = ".rds"); f3 <- tempfile(fileext = ".R")
  saveRDS(list(cf = cf, nudge = nudge, s = s, lib = .libPaths()), f1)
  writeLines(c(sprintf('x <- readRDS("%s"); .libPaths(x$lib); suppressMessages(library(polspline))', gsub("\\\\", "/", f1)),
               'quiet <- function(expr) { out <- NULL; capture.output(out <- withCallingHandlers(expr, warning = function(w) stop(w))); out }',
               paste("fitit_here <-", paste(deparse(fitit_here), collapse = "\n")),
               'f <- tryCatch(fitit_here(x$cf, x$nudge, x$s), error = function(e) NULL)',
               sprintf('saveRDS(f, "%s")', gsub("\\\\", "/", f2))), f3)
  system2(file.path(R.home("bin"), "Rscript"), f3, stdout = FALSE, stderr = FALSE)
  if (file.exists(f2)) readRDS(f2) else NULL
}
fitit_here <- function(cf, nudge = 0, s = 0) {
  a <- list()
  mk <- function(v) if (nudge == 0) v else v * (1 + nudge * sin(s * 7.3 * v))
  a$uncensored <- mk(cf$unc)
  if (!is.null(cf$right)) a$right <- mk(cf$right)
  if (!is.null(cf$left)) a$left <- mk(cf$left)
  if (!is.null(cf$int)) a$interval <- mk(cf$int)
  for (nm in c("lbound", "ubound", "nknots", "knots", "penalty", "delete")) if (!is.null(cf[[nm]])) a[[nm]] <- cf[[nm]]
  quiet(do.call(oldlogspline, a))
}
nfit <- 0
for (cf in configs) {
  cf$unc <- round(cf$unc, 3)
  if (!is.null(cf$right)) cf$right <- round(cf$right, 3)
  if (!is.null(cf$left)) cf$left <- round(cf$left, 3)
  if (!is.null(cf$int)) cf$int <- round(cf$int, 3)
  f <- tryCatch(fitit(cf), error = function(e) { message("skipped: ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  stable <- TRUE
  for (s in 1:3) {
    g <- tryCatch(fitit(cf, 1e-13, s), error = function(e) NULL)
    if (is.null(g) || length(g$coef) != length(f$coef) || any(abs(g$coef - f$coef) > 1e-6 * abs(f$coef)) || length(g$logl) != length(f$logl)) { stable <- FALSE; break }
  }
  if (!stable) { message("unstable fit skipped"); next }
  nfit <- nfit + 1
  nu <- length(cf$unc); nr <- length(cf$right); nl <- length(cf$left)
  iv <- if (is.null(cf$int)) numeric(0) else as.vector(t(cf$int))
  pre <- c(nu, nr, nl, length(iv) / 2, as.numeric(!is.null(cf$lbound)), if (is.null(cf$lbound)) 0 else cf$lbound,
           as.numeric(!is.null(cf$ubound)), if (is.null(cf$ubound)) 0 else cf$ubound,
           if (is.null(cf$nknots)) -1 else cf$nknots, length(cf$knots), if (is.null(cf$penalty)) -1 else cf$penalty,
           if (is.null(cf$delete)) 1 else as.numeric(cf$delete), cf$knots, cf$unc, cf$right, cf$left, iv)
  add <- function(what, x, v, rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <<- case("olfit", c(pre, what, x), as.numeric(v), rel = rel, abs = abs)
  add(0, 0, length(f$knots), 0, 0)
  for (i in seq_along(f$coef)) add(1, i - 1, f$coef[i])
  for (i in seq_along(f$knots)) add(2, i - 1, f$knots[i])
  for (i in 1:4) add(3, i - 1, f$bound[i])
  add(4, 0, length(f$logl), 0, 0)
  for (i in seq_along(f$logl)) add(5, i - 1, f$logl[i])
  add(6, 0, f$penalty); add(7, 0, f$sample, 0, 0)
  xs <- quantile(cf$unc, c(0.1, 0.5, 0.9), names = FALSE)
  for (x in xs) { add(8, x, doldlogspline(x, f)); add(9, x, poldlogspline(x, f)) }
  for (p in c(0.1, 0.5, 0.9)) add(10, p, qoldlogspline(p, f))
}
message("fits: ", nfit)
emit("polspline_oldlog", "polspline", list(cases))
