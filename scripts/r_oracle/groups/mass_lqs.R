# MASS lqs (lqs, lts, lms, S) and cov.rob (mve, mcd, classical) under set.seed.
#   "lqs" (seed, n, p0, method 0 lqs 1 lts 2 lms 3 S, quantile (-1 default), psamp (0 default), nsamp (-1 best, -2 exact, -3 sample, else count), adjust, intercept, k0, mode, X[n p0] col-major, y[n])
#       mode 0 crit, 1 weighted sum of coefficients, 2 scale, 3 second scale, 4 weighted sum of residuals, 5 weighted sum of bestone, 6 singular samples
#   "covrob" (seed, n, p, method 0 mve 1 mcd 2 classical, quantile (-1 default), nsamp, mode, X[n p] col-major)
#       mode 0 crit, 1 weighted center, 2 weighted cov, 3 weighted best, 4 singular samples, 5 number in best
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262401)
mnames <- c("lqs", "lts", "lms", "S")
for (rep in 1:48) {
  n <- sample(c(12, 16, 25, 40, 60), 1); p0 <- sample(1:3, 1)
  X <- matrix(rnorm(n * p0), n, p0); b <- rnorm(p0 + 1)
  y <- as.vector(b[1] + X %*% b[-1] + rnorm(n, 0, 0.5))
  bad <- sample(n, max(1, n %/% 5)); y[bad] <- y[bad] + rnorm(length(bad), 8, 3); X[bad[1], 1] <- X[bad[1], 1] * 6
  method <- (rep - 1) %% 4; seed <- sample(1:1000000, 1)
  q <- if (rep %% 5 == 0 && method != 2 && method != 3) floor(n * 0.6) else -1
  nsamp <- if (rep %% 3 == 0) 200 else -1
  psamp <- if (rep %% 7 == 0) p0 + 2 else 0
  adjust <- as.numeric(rep %% 6 != 0); k0 <- if (method == 3) c(1.548, 2)[rep %% 2 + 1] else 1.548
  intercept <- as.numeric(rep %% 11 != 0)
  args <- list(X, y, intercept = intercept == 1, method = mnames[method + 1], k0 = k0,
               control = list(psamp = if (psamp == 0) NA else psamp, nsamp = if (nsamp == -1) "best" else nsamp, adjust = adjust == 1))
  if (q > 0) args$quantile <- q
  set.seed(seed)
  z <- tryCatch(do.call(lqs, args), error = function(e) NULL)
  if (is.null(z)) next
  a <- c(seed, n, p0, method, q, psamp, nsamp, adjust, intercept, k0)
  tail <- c(as.vector(X), y)
  nsing <- as.numeric(sub(" .*", "", z$sing))
  add("lqs", c(a, 0, tail), z$crit)
  add("lqs", c(a, 1, tail), wsum(z$coefficients))
  add("lqs", c(a, 2, tail), z$scale[1])
  add("lqs", c(a, 3, tail), z$scale[2])
  add("lqs", c(a, 4, tail), wsum(z$residuals), rel = 1e-8, abs = 1e-8)
  add("lqs", c(a, 5, tail), wsum(z$bestone), rel = 0, abs = 0)
  add("lqs", c(a, 6, tail), nsing, rel = 0, abs = 0)
}
cmeth <- c("mve", "mcd", "classical")
for (rep in 1:36) {
  n <- sample(c(14, 20, 30, 50, 80), 1); p <- sample(2:4, 1)
  X <- matrix(rnorm(n * p), n, p) %*% matrix(rnorm(p * p), p); bad <- sample(n, n %/% 6); X[bad, ] <- X[bad, ] + 6
  method <- (rep - 1) %% 3; seed <- sample(1:1000000, 1)
  q <- if (rep %% 4 == 0) floor(n * 0.7) else -1
  nsamp <- if (rep %% 5 == 0) 300 else -1
  args <- list(X, method = cmeth[method + 1], nsamp = if (nsamp == -1) "best" else nsamp)
  if (q > 0) args$quantile.used <- q
  set.seed(seed)
  z <- tryCatch(do.call(cov.rob, args), error = function(e) NULL)
  if (is.null(z)) next
  a <- c(seed, n, p, method, q, nsamp); tail <- as.vector(X)
  if (method < 2) {
    add("covrob", c(a, 0, tail), z$crit)
    add("covrob", c(a, 3, tail), wsum(z$best), rel = 0, abs = 0)
    add("covrob", c(a, 4, tail), as.numeric(sub(" .*", "", z$msg)), rel = 0, abs = 0)
    add("covrob", c(a, 5, tail), length(z$best), rel = 0, abs = 0)
  }
  add("covrob", c(a, 1, tail), wsum(z$center))
  add("covrob", c(a, 2, tail), wsum(z$cov))
}
emit("mass_lqs", "MASS", list(cases))
