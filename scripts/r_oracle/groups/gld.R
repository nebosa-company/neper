# gld: qgl, dqgl and rgl in the fkml and rs parameterisations.
#   "q" (param 0 fkml 1 rs, p, l1, l2, l3, l4) "dq" (param, p, l2, l3, l4) "r" (param, seed, l1, l2, l3, l4, index)
suppressMessages(library(gld))
cases <- list()
add <- function(fn, args, want, tol = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261118)
for (rep in 1:40) {
  pm <- rep %% 2; param <- c("fkml", "rs")[pm + 1]
  l1 <- rnorm(1); l2 <- runif(1, 0.3, 3); l3 <- if (rep %% 7 == 0 && pm == 0) 0 else runif(1, 0.1, 1.5); l4 <- if (rep %% 11 == 0 && pm == 0) 0 else runif(1, 0.1, 1.5)
  ok <- tryCatch({ qgl(0.5, l1, l2, l3, l4, param = param); TRUE }, error = function(e) FALSE); if (!ok) next
  for (p in c(0.01, 0.2, 0.5, 0.83, 0.99)) { add("q", c(pm, p, l1, l2, l3, l4), qgl(p, l1, l2, l3, l4, param = param)); add("dq", c(pm, p, l2, l3, l4), dqgl(p, l1, l2, l3, l4, param = param)) }
  sd <- sample(1:100000, 1); set.seed(sd); v <- rgl(5, l1, l2, l3, l4, param = param); for (j in 1:5) add("r", c(pm, sd, l1, l2, l3, l4, j - 1), v[j])
}
emit("gld", "gld", list(cases))
