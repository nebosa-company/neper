# caret: createFolds(list = FALSE) for a numeric y. Args: (seed, k, n, y[n]); the answer is sum(position * fold)
suppressMessages(library(caret))
cases <- list()
set.seed(20262400)
for (rep in 1:60) {
  sd <- sample(1:100000, 1); n <- sample(12:120, 1); k <- sample(2:8, 1)
  y <- switch(rep %% 4 + 1, rnorm(n), round(rnorm(n, 50, 20), 1), round(runif(n, 0, 1000)), sample(c(0.001, 0.5, 2, 1500, 12345), n, TRUE) * runif(1, 0.5, 2))
  set.seed(sd); f <- tryCatch(createFolds(y, k = k, list = FALSE), error = function(e) NULL)
  if (is.null(f)) next
  cases[[length(cases) + 1]] <- case("cfn", c(sd, k, n, y), sum(seq_along(f) * f), rel = 1e-12, abs = 1e-12)
}
emit("carets_cfn", "caret", list(cases))
