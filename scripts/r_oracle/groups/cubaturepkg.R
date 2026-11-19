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
# infinite limits: "inf" args as "box" with an infinite end written as +-1e100; the integrand exp(-sum x^2) (id 0) over boxes with one or two infinite ends per dimension
for (rep in 1:16) {
  d <- sample(1:2, 1); lo <- numeric(d); hi <- numeric(d)
  for (k in 1:d) { kind <- sample(1:3, 1); if (kind == 1) { lo[k] <- -Inf; hi[k] <- Inf } else if (kind == 2) { lo[k] <- runif(1, -1, 0.5); hi[k] <- Inf } else { lo[k] <- -Inf; hi[k] <- runif(1, -0.5, 1) } }
  r <- hcubature(fs[[1]], lo, hi, tol = 1e-10, maxEval = 5e5)
  cases[[length(cases) + 1]] <- case("inf", c(0, d, ifelse(is.infinite(lo), -1e100, lo), ifelse(is.infinite(hi), 1e100, hi)), r$integral, rel = 1e-7, abs = 1e-9)
}
# hcubature's own recursion for 2 and 3 dimensions: "hg" args (id, d, lo[d], hi[d], tol, maxEval, which) with which 0 the integral, 1 the error estimate, 2 the evaluation count
for (rep in 1:24) {
  id <- (rep - 1) %% 4; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-4, 1e-6)[1 + (rep %% 3 == 0)]
  r <- hcubature(fs[[id + 1]], lo, hi, tol = tl, maxEval = 20000)
  if (r$functionEvaluations >= 20000) next
  a <- c(id, d, lo, hi, tl, 20000)
  cases[[length(cases) + 1]] <- case("hg", c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("hg", c(a, 1), r$error, rel = 1e-6, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("hg", c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
}
emit("cubaturepkg", "cubature", list(cases))
