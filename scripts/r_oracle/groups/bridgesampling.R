# bridgesampling: bridge_sampler on a samples matrix with the normal proposal (use_neff = FALSE).
#   args: (seed, id, n, p, samples row-wise...)   fn "logml" "niter" (normal), "logml3" "niter3" (warp3)
#   id 0: log posterior -0.5 sum((th - c(1, -2, 0.5, 3, -1)[1:p])^2 / c(1, 4, 0.25, 2, 1)[1:p])
#   id 1: log posterior -0.5 (th1^2 / 4 + (th2 - 0.25 th1^2)^2)    (p = 2)
suppressMessages(library(bridgesampling))
cases <- list(); prev <- NULL
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-8)
mu <- c(1, -2, 0.5, 3, -1); s2 <- c(1, 4, 0.25, 2, 1)
lp0 <- function(th, data) -0.5 * sum((th - mu[seq_along(th)])^2 / s2[seq_along(th)])
lp1 <- function(th, data) -0.5 * (th[1]^2 / 4 + (th[2] - 0.25 * th[1]^2)^2)
set.seed(20261115)
for (rep in 1:24) {
  id <- if (rep %% 4 == 0) 1 else 0
  p <- if (id == 1) 2 else c(1, 2, 3, 5)[(rep - 1) %% 4 + 1]
  n <- c(200, 301, 400, 250, 500, 120, 351, 300)[(rep - 1) %% 8 + 1]
  sm <- if (id == 0) sapply(seq_len(p), function(j) rnorm(n, mu[j], sqrt(s2[j]))) else cbind(rnorm(n, 0, 2), rnorm(n, 0.25 * 3, 1))
  sm <- matrix(round(sm, 4), n, p); colnames(sm) <- paste0("t", 1:p)
  seed <- sample(1e6, 1); set.seed(seed)
  b <- tryCatch(suppressWarnings(bridge_sampler(sm, log_posterior = if (id == 0) lp0 else lp1, data = list(),
                  lb = setNames(rep(-Inf, p), colnames(sm)), ub = setNames(rep(Inf, p), colnames(sm)), use_neff = FALSE, silent = TRUE)), error = function(e) NULL)
  if (is.null(b)) next
  a <- c(seed, id, n, p, as.vector(t(sm)))
  add("logml", a, b$logml); add("niter", a, b$niter)
  set.seed(seed)
  w <- tryCatch(suppressWarnings(bridge_sampler(sm, log_posterior = if (id == 0) lp0 else lp1, data = list(), method = "warp3",
                  lb = setNames(rep(-Inf, p), colnames(sm)), ub = setNames(rep(Inf, p), colnames(sm)), use_neff = FALSE, silent = TRUE)), error = function(e) NULL)
  if (!is.null(w) && is.finite(w$logml)) { add("logml3", a, w$logml); add("niter3", a, w$niter) }
  if (!is.null(prev)) { add("bf", c(prev$logml, b$logml), bf(prev, b)$bf); add("post", c(prev$logml, b$logml, 0.3, 0.7), post_prob(prev, b, prior_prob = c(0.3, 0.7))[[1]]) }
  prev <- b
}
#   bounded: fn "logmlb" "nitb" "logml3b" "niter3b", args as above with id 2 (p = 2: th1 ~ Gamma(3, 1) on (0, Inf), th2 ~ Beta(2, 3) on (0, 1)) or id 3 (p = 1: 2 - Gamma(2, 1), upper bound 2)
lp2 <- function(th, data) 2 * log(th[1]) - th[1] + log(th[2]) + 2 * log(1 - th[2])
lp3 <- function(th, data) log(2 - th[1]) - (2 - th[1])
for (rep in 1:12) {
  id <- c(2, 3, 2, 3)[(rep - 1) %% 4 + 1]; p <- if (id == 2) 2 else 1
  n <- c(300, 400, 250, 500)[(rep - 1) %% 4 + 1]
  sm <- if (id == 2) cbind(rgamma(n, 3, 1), rbeta(n, 2, 3)) else matrix(2 - rgamma(n, 2, 1), n, 1)
  sm <- matrix(pmin(pmax(round(sm, 5), if (id == 2) 1e-5 else -1e9), if (id == 2) c(1e9, 1 - 1e-5) else 2 - 1e-5), n, p, byrow = FALSE)
  if (id == 2) sm[, 2] <- pmin(sm[, 2], 1 - 1e-5)
  colnames(sm) <- paste0("t", 1:p)
  lb <- setNames(if (id == 2) c(0, 0) else -Inf, colnames(sm)); ub <- setNames(if (id == 2) c(Inf, 1) else 2, colnames(sm))
  lpf <- if (id == 2) lp2 else lp3
  seed <- sample(1e6, 1); a <- c(seed, id, n, p, as.vector(t(sm)))
  set.seed(seed); b <- tryCatch(suppressWarnings(bridge_sampler(sm, log_posterior = lpf, data = list(), lb = lb, ub = ub, use_neff = FALSE, silent = TRUE)), error = function(e) NULL)
  if (!is.null(b) && is.finite(b$logml)) { add("logmlb", a, b$logml); add("niterb", a, b$niter) }
  set.seed(seed); w <- tryCatch(suppressWarnings(bridge_sampler(sm, log_posterior = lpf, data = list(), lb = lb, ub = ub, method = "warp3", use_neff = FALSE, silent = TRUE)), error = function(e) NULL)
  if (!is.null(w) && is.finite(w$logml)) { add("logml3b", a, w$logml); add("niter3b", a, w$niter) }
}
emit("bridgesampling", "bridgesampling", list(cases))
