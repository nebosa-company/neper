# mixtools: regmixEM, random starts included (set.seed is called just before the fit, after the data are drawn).
suppressMessages(library(mixtools))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
quiet <- function(e) { r <- NULL; capture.output(r <- try(suppressWarnings(e), silent = TRUE)); r }
rows <- function(m) as.vector(t(m))
# regmixEM with a log of every restart: sing = number of collapsed lambda/sigma, dec = loglik step that triggered it
assign("rlog", list(), .GlobalEnv)
regfit <- local({
  txt <- paste(deparse(mixtools::regmixEM), collapse = "\n")
  txt <- sub("restarts <- restarts + 1", "restarts <- restarts + 1; assign(\"rlog\", c(get(\"rlog\", .GlobalEnv), list(c(sing = sing, dec = if (is.na(newobsloglik)) NA else newobsloglik - obsloglik))), .GlobalEnv)", txt, fixed = TRUE)
  f <- eval(parse(text = txt)); environment(f) <- environment(mixtools::regmixEM); f })
# a restart is reproducible when a lambda/sigma collapsed (or the loglik went NaN/Inf), or the loglik fell by far more than an ulp
restart_ok <- function() all(vapply(get("rlog", .GlobalEnv), function(z) z[["sing"]] > 0 || is.na(z[["dec"]]) || abs(z[["dec"]]) > 1e-6, TRUE))
#   rg   args: (sel, idx, seed, k, arbmean, arbvar, addint, n, q, nl, nb, ns, y[n], x[n x q, row-major], lambda[nl], beta[nb: p x k row-major, or p], sigma[ns])
#        sel 1 loglik, 2 iterations, 3 restarts, 4 lambda[idx], 5 beta[idx], 6 sigma[idx], 7 scale[idx], 8 sum_i posterior[i, idx] * i, 9 all.loglik[idx], 10 length(all.loglik)
rg_case <- function(y, x, k, arbmean, arbvar, addint, lam, be, sg, seed) {
  n <- length(y); x <- as.matrix(x); q <- ncol(x); p <- q + addint
  set.seed(seed)
  bem <- if (length(be)) { if (arbmean) matrix(be, p, k, byrow = TRUE) else matrix(be, p, 1) } else NULL
  assign("rlog", list(), .GlobalEnv)
  r <- quiet(regfit(y, x, lambda = if (length(lam)) lam else NULL, beta = bem, sigma = if (length(sg)) sg else NULL, k = k, addintercept = as.logical(addint),
                      arbmean = as.logical(arbmean), arbvar = as.logical(arbvar), epsilon = 1e-8, maxit = 1000))
  if (inherits(r, "try-error") || length(r$all.loglik) > 1000 || !restart_ok() || abs(diff(tail(r$all.loglik, 2))) < 1e-11) return(invisible())  # a restart off a one-ulp loglik decrease at the plateau (or a stop on such a step) is rounding noise, not reproducible
  hd <- c(seed, k, arbmean, arbvar, addint, n, q, length(lam), length(be), length(sg), y, rows(x), lam, be, sg)
  a <- function(sel, idx, want, rel = 1e-9) add("rg", c(sel, idx, hd), want, rel = rel)
  a(1, 0, r$loglik); a(2, 0, length(r$all.loglik) - 1, rel = 0); a(3, 0, r$restarts, rel = 0)
  for (j in seq_len(k)) { a(4, j, r$lambda[j]); a(8, j, sum(r$posterior[, j] * seq_len(n))) }
  bs <- if (arbmean) rows(r$beta) else as.vector(r$beta)
  for (j in seq_along(bs)) a(5, j, bs[j])
  for (j in seq_along(r$sigma)) a(6, j, r$sigma[j])
  if (!arbmean) for (j in seq_len(k)) a(7, j, r$scale[j])
  a(9, 1, r$all.loglik[1]); a(9, length(r$all.loglik), r$all.loglik[length(r$all.loglik)]); a(10, 0, length(r$all.loglik), rel = 0)
}
rgdraw <- function(k, q, n) {
  lam <- runif(k); lam <- lam / sum(lam); comp <- sample(k, n, replace = TRUE, prob = lam)
  x <- matrix(round(runif(n * q, -2, 2), 3), n, q); b0 <- c(-2, 2, 0)[1:k] * 2; b <- matrix(rnorm(q * k, 0, 2), q, k)
  y <- b0[comp] + rowSums(x * t(b[, comp, drop = FALSE])) + rnorm(n, 0, 0.5)
  list(y = round(y, 4), x = x)
}
set.seed(20261302)
for (rep in 1:4) {                           # given starting values
  k <- 2; q <- sample(1:2, 1); n <- sample(40:80, 1); d <- rgdraw(k, q, n)
  be <- as.vector(t(matrix(rnorm((q + 1) * k, 0, 2), q + 1, k)))
  rg_case(d$y, d$x, k, 1, 1, 1, c(0.5, 0.5), be, c(1, 1), 1)
  rg_case(d$y, d$x, k, 1, 0, 1, c(0.5, 0.5), be, 1, 2)
}
for (rep in 1:6) {                           # random starts
  k <- sample(2:3, 1); q <- sample(1:3, 1); n <- sample(50:90, 1); d <- rgdraw(k, q, n)
  rg_case(d$y, d$x, k, 1, 1, 1, numeric(0), numeric(0), numeric(0), 100 + rep)
  if (rep %% 2 == 0) rg_case(d$y, d$x, k, 1, 0, 1, numeric(0), numeric(0), numeric(0), 200 + rep)
  if (rep %% 3 == 0) rg_case(d$y, d$x, k, 0, 1, 1, numeric(0), numeric(0), numeric(0), 300 + rep)
  if (rep %% 5 == 0) rg_case(d$y, cbind(1, d$x), k, 1, 1, 0, numeric(0), numeric(0), numeric(0), 400 + rep)
}
set.seed(20261303)
for (rep in 1:24) {                          # small samples: random starts that restart off a collapsed lambda or sigma
  k <- sample(2:3, 1); q <- sample(1:3, 1); n <- sample(12:30, 1); d <- rgdraw(k, q, n)
  rg_case(d$y, d$x, k, 1, 1, 1, numeric(0), numeric(0), numeric(0), 500 + rep)
  if (rep %% 4 == 0) rg_case(d$y, d$x, k, 0, 1, 1, numeric(0), numeric(0), numeric(0), 600 + rep)
}

emit("mixtools_reg", "mixtools", list(cases))
