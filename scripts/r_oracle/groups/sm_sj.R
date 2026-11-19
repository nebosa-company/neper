# sm: hsj, the Sheather-Jones bandwidth (unbinned, below 100 observations). Args: (n, x[n]).
suppressMessages(library(sm))
cases <- list()
set.seed(20262322)
for (rep in 1:30) {
  n <- sample(20:90, 1); x <- if (rep %% 2 == 0) rnorm(n) else c(rnorm(n %/% 2), rnorm(n - n %/% 2, 3, 0.6))
  r <- tryCatch(hsj(x), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hsj", c(n, x), r, rel = 1e-9, abs = 1e-12)
}
emit("sm_sj", "sm", list(cases))
