# cubaturepkg: hcubature and pcubature integrals of four smooth integrands over boxes of dimension 1 to 3.
#   args: (id 0 exp(-sum x^2), 1 prod cos, 2 1/(1+sum x), 3 (sum x)^2 exp(-prod x); d; lo (d); hi (d)). The package stops at its tolerance 1e-10, so the comparison is at rel 1e-8.
suppressMessages(library(cubature))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
fs <- list(function(x) exp(-sum(x^2)), function(x) prod(cos(x)), function(x) 1 / (1 + sum(x)), function(x) sum(x)^2 * exp(-prod(x)))
set.seed(20262013)
for (rep in 1:24) {
  d <- sample(1:3, 1); id <- (rep - 1) %% 4; lo <- runif(d, 0, 0.5); hi <- lo + runif(d, 0.3, 1.2)
  r <- if (rep %% 2 == 0) hcubature(fs[[id + 1]], lo, hi, tol = 1e-10, maxEval = 2e5) else pcubature(fs[[id + 1]], lo, hi, tol = 1e-10, maxEval = 2e5)
  add("box", c(id, d, lo, hi), r$integral)
}
emit("cubaturepkg", "cubature", list(cases))
