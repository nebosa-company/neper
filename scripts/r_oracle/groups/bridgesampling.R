# bridgesampling: bridge_sampler on a samples matrix with the normal proposal (use_neff = FALSE).
#   args: (seed, id, n, p, samples row-wise...)   fn "logml" "niter"
#   id 0: log posterior -0.5 sum((th - c(1, -2, 0.5, 3, -1)[1:p])^2 / c(1, 4, 0.25, 2, 1)[1:p])
#   id 1: log posterior -0.5 (th1^2 / 4 + (th2 - 0.25 th1^2)^2)    (p = 2)
suppressMessages(library(bridgesampling))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-8)
mu <- c(1, -2, 0.5, 3, -1); s2 <- c(1, 4, 0.25, 2, 1)
lp0 <- function(th, data) -0.5 * sum((th - mu[seq_along(th)])^2 / s2[seq_along(th)])
lp1 <- function(th, data) -0.5 * (th[1]^2 / 4 + (th[2] - 0.25 * th[1]^2)^2)
set.seed(20261115)
for (rep in 1:8) {
  id <- if (rep %% 4 == 0) 1 else 0
  p <- if (id == 1) 2 else c(1, 2, 3, 5)[(rep - 1) %% 4 + 1]
  n <- c(200, 301, 400, 250, 500, 120, 351, 300)[rep]
  sm <- if (id == 0) sapply(seq_len(p), function(j) rnorm(n, mu[j], sqrt(s2[j]))) else cbind(rnorm(n, 0, 2), rnorm(n, 0.25 * 3, 1))
  sm <- matrix(round(sm, 4), n, p); colnames(sm) <- paste0("t", 1:p)
  seed <- sample(1e6, 1); set.seed(seed)
  b <- tryCatch(suppressWarnings(bridge_sampler(sm, log_posterior = if (id == 0) lp0 else lp1, data = list(),
                  lb = setNames(rep(-Inf, p), colnames(sm)), ub = setNames(rep(Inf, p), colnames(sm)), use_neff = FALSE, silent = TRUE)), error = function(e) NULL)
  if (is.null(b)) next
  a <- c(seed, id, n, p, as.vector(t(sm)))
  add("logml", a, b$logml); add("niter", a, b$niter)
}
emit("bridgesampling", "bridgesampling", list(cases))
