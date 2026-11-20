# gamlss lms(y, x, families = "BCCG", calibration = FALSE): the initial NO fit, the BCCG fit with pb(x) in mu, sigma and nu, and the kept model.
# A scenario opens with a case whose args are [n, out kind, out index, y (n), x (n)]; the cases after it carry n = 0 and read the same result.
# out kinds: 0 kept family (0 NO, 1 BCCG), 1 AIC of the initial NO fit, 2 AIC of the BCCG fit, 3 G.deviance of the kept model, 4 df.fit, 5 iter, 6 fitted mu i, 7 sigma i, 8 nu i (BCCG)
suppressMessages(library(gamlss))
pdf(NULL)
cases <- list()
run <- function(y, x, only_initial = FALSE) {
  n <- length(y)
  m <- suppressWarnings(suppressMessages(invisible(capture.output(r <- lms(y, x, families = "BCCG", calibration = FALSE, legend = FALSE)))))
  bc <- r$family[1] == "BCCG"
  fits <- r$fits
  first <- TRUE
  # R-side reason for the BCCG tolerance: the nu smoother's ML lambda sits near 4.6e6 and gamlss.pb stops on an absolute lambda change of 1e-7,
  # about 100 ulps, so the stopping iteration and with it the BCCG fit values are floating-point noise (relative 1e-5); a kept NO model has no such smoother and is checked at 1e-9
  tol <- if (bc) 1e-4 else 1e-9
  add <- function(kind, idx, want, rel = tol) {
    h <- if (first) c(n, kind, idx, y, x) else c(0, kind, idx)
    cases[[length(cases) + 1]] <<- case("lms", h, want, rel = rel, abs = if (rel == 0) 0 else 1e-11)
    first <<- FALSE
  }
  add(1, 0, unname(fits[names(fits) != "BCCG"][1]), 1e-9)
  if (only_initial) return(invisible())
  add(0, 0, as.numeric(bc), 0)
  add(2, 0, if ("BCCG" %in% names(fits)) unname(fits["BCCG"]) else NA, 1e-4)
  add(3, 0, r$G.deviance)
  add(4, 0, r$df.fit)
  add(5, 0, r$iter, 0)
  for (i in c(1, n %/% 3, 2 * n %/% 3, n)) {
    add(6, i - 1, fitted(r, "mu")[i])
    add(7, i - 1, fitted(r, "sigma")[i])
    if (bc) add(8, i - 1, fitted(r, "nu")[i])
  }
}
set.seed(20261901)
n <- 100
x <- round(runif(n, 0.2, 5), 3)
y <- round(exp(0.8 + 0.25 * x + (0.25 + 0.04 * x) * rnorm(n)) + 0.0 * x, 4)
run(y, x)
y2 <- round(2 + sin(x) + 0.3 * rnorm(n), 4) + 4
run(y2, x)
set.seed(7)
y3 <- round(6 + 0.5 * x + 0.6 * rnorm(n), 4)
run(y3, x)
# a draw where NO is kept and the refit takes one more iteration at c.crit 0.01 than at 0.02, so that criterion is checked
set.seed(2108)
x4 <- round(runif(n, 0.2, 5), 3)
y4 <- round(8 + 0.5 * x4 + (0.4 + 0.06 * x4) * rnorm(n), 4)
run(y4, x4)
emit("gamlss_lms", c("gamlss", "gamlss.dist"), list(cases))
