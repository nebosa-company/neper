# sm: h.select(x, method = "cv"), one variable, unbinned. Args: (n, x[n]) or hcvreg (n, x[n], y[n]).
suppressMessages(library(sm))
cases <- list()
set.seed(20262330)
for (rep in 1:30) {
  n <- sample(20:90, 1); x <- if (rep %% 2 == 0) rnorm(n) else c(rnorm(n %/% 2), rnorm(n - n %/% 2, 3, 0.6))
  r <- tryCatch(h.select(x, method = "cv"), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hcvsel", c(n, x), r, rel = 1e-7, abs = 1e-12)
}
for (rep in 1:20) {
  n <- sample(20:90, 1); x <- rnorm(n); y <- sin(x) + rnorm(n, 0, 0.3)
  r <- tryCatch(h.select(x, y, method = "cv"), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hcvreg", c(n, x, y), r, rel = 1e-7, abs = 1e-12)
}
for (rep in 1:20) {
  n <- sample(20:90, 1); x <- rnorm(n); y <- sin(x) + rnorm(n, 0, 0.3)
  r <- tryCatch(h.select(x, y, method = "aicc"), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("haicc", c(n, x, y), r, rel = 1e-6, abs = 1e-12)
  r <- tryCatch(h.select(x, y, method = "df", df = 5), error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <- case("hdf", c(n, x, y), r, rel = 1e-6, abs = 1e-12)
}
emit("sm_hsel", "sm", list(cases))
