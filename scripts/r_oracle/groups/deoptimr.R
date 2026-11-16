# DEoptimR::JDEoptim under set.seed: par, value, iter, convergence.
#   args: (id, seed, d, np, maxiter, lower[d], upper[d], q)  q 0..d-1 par, d value, d+1 iter, d+2 convergence
#   ids: 0 sphere, 1 Rosenbrock, 2 double well sum((x*x - 1)^2 + 0.3 x), 3 sphere with x1 + x2 >= 1 (inequality), 4 sphere with x1 + x2 = 1 (equality), 5 sphere with both
suppressMessages(library(DEoptimR))
cases <- list()
sphere <- function(x) { s <- 0; for (i in seq_along(x)) { t <- x[i] - i / 4; s <- s + t * t }; s }
rosen <- function(x) { s <- 0; for (i in seq_len(length(x) - 1)) { t <- x[i + 1] - x[i] * x[i]; s <- s + (100 * t * t + (1 - x[i]) * (1 - x[i])) }; s }
rast <- function(x) { s <- 0; for (i in seq_along(x)) s <- s + ((x[i] * x[i] - 1) * (x[i] * x[i] - 1) + 0.3 * x[i]); s }
fns <- list(sphere, rosen, rast, sphere, sphere, sphere)
cons <- list(NULL, NULL, NULL, function(x) 1 - x[1] - x[2], function(x) x[1] + x[2] - 1, function(x) c(x[1] + x[2] - 1, 0.5 - x[1]))
meqs <- c(0, 0, 0, 0, 1, 1)
for (id in 0:5) for (rep in 1:5) {
  d <- if (id == 1) sample(2:3, 1) else sample(2:4, 1); seed <- 100 * id + rep
  lo <- rep(-2, d); hi <- rep(3, d); np <- 10 * d; mi <- 250
  set.seed(seed)
  r <- suppressWarnings(JDEoptim(lo, hi, fns[[id + 1]], constr = cons[[id + 1]], meq = meqs[id + 1], NP = np, maxiter = mi))
  out <- c(r$par, r$value, r$iter, r$convergence)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("de", c(id, seed, d, np, mi, lo, hi, q - 1), out[q], rel = 1e-9, abs = 1e-11)
}
emit("deoptimr", "DEoptimR", list(cases))
