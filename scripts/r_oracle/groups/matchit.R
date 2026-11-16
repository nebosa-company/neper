# MatchIt nearest-neighbour matching without replacement on the logistic propensity score.
#   args: (n, p, ratio, t[n], x[n*p] row-major)
#   fn "weights" (matching weights weighted by position), "nmatched" (units with positive weight)
suppressMessages(library(MatchIt))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261231)
for (rep in 1:24) {
  n <- sample(50:200, 1); p <- sample(1:3, 1); ratio <- sample(1:2, 1)
  x <- matrix(rnorm(n * p), n); t <- rbinom(n, 1, plogis(x[, 1] * 0.8 - 0.8)); if (sum(t) < 5 || sum(t) * (ratio + 1) > n * 0.9) next
  d <- data.frame(t, x); names(d)[-1] <- paste0("x", seq_len(p))
  m <- tryCatch(suppressWarnings(matchit(as.formula(paste("t ~", paste0("x", seq_len(p), collapse = " + "))), d, method = "nearest", ratio = ratio)), error = function(e) NULL)
  if (is.null(m)) next
  a <- c(n, p, ratio, t, as.vector(t(x)))
  add("weights", a, sum(m$weights * seq_along(m$weights))); add("nmatched", a, sum(m$weights > 0))
}
emit("matchit", "MatchIt", list(cases))
