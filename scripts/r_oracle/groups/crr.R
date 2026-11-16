# cmprsk::crr point estimates (variance = FALSE): Fine-Gray coefficients, log likelihood and null log likelihood.
#   args: (n, ncov, ncov2, ncg, q, time[n] sorted, status[n] 0/1/2, cengroup[n] 0.., cov1 col-major[n*ncov], cov2 col-major[n*ncov2])
#   q 0..np-1 coefficient, np loglik, np+1 loglik.null; time function of column j of cov2: j = 0 log(1 + t), j = 1 t
suppressMessages(library(cmprsk))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261117)
for (rep in 1:40) {
  n <- sample(30:90, 1); nc1 <- sample(1:3, 1); nc2 <- if (rep %% 3 == 0) sample(1:2, 1) else 0; ncg <- if (rep %% 4 == 0) 2 else 1
  tm <- if (rep %% 2 == 0) round(rexp(n, 0.3) + 0.01, 1) else rexp(n, 0.3) + 0.01
  x1 <- matrix(rnorm(n * nc1), n, nc1)
  st <- ifelse(runif(n) < 0.3, 0, ifelse(runif(n) < 0.5 + 0.2 * (x1[, 1] > 0), 1, 2))
  o <- order(tm); tm <- tm[o]; st <- st[o]; x1 <- x1[o, , drop = FALSE]
  cg <- sample(0:(ncg - 1), n, TRUE)
  x2 <- if (nc2 > 0) matrix(rnorm(n * nc2), n, nc2) else NULL
  tf <- if (nc2 == 1) function(u) cbind(log(1 + u)) else if (nc2 == 2) function(u) cbind(log(1 + u), u) else NULL
  fit <- tryCatch(suppressWarnings(crr(tm, st, x1, x2, tf, cengroup = cg + 1, variance = FALSE)), error = function(e) NULL)
  if (is.null(fit) || !fit$converged) next
  np <- nc1 + nc2; vals <- c(fit$coef, fit$loglik, fit$loglik.null)
  for (q in seq_along(vals)) add("crr", c(n, nc1, nc2, ncg, q - 1, tm, st, cg, as.vector(x1), if (nc2 > 0) as.vector(x2)), vals[q])
}
emit("crr", "cmprsk", list(cases))
