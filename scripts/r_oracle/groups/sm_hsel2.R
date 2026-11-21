# sm: h.select for regression on two covariates (hr2, hr2o), layouts below.
suppressMessages(library(sm))
cases <- list()
set.seed(20262331)
# hr2 (n, kind 0 cv 1 df 2 aicc, which, x[n], y[n], z[n]): h.select(cbind(x, y), z, method) scaled structure, df 12 by default
for (rep in 1:10) {
  n <- sample(40:70, 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n, 0, 0.8); z <- sin(x) + 0.5 * y + rnorm(n, 0, 0.3)
  for (kd in 0:2) {
    r <- tryCatch(h.select(cbind(x, y), z, method = c("cv", "df", "aicc")[kd + 1]), error = function(e) NULL)
    if (!is.null(r) && all(is.finite(r))) for (w in 1:2) cases[[length(cases) + 1]] <- case("hr2", c(n, kd, w - 1, x, y, z), r[w], rel = 1e-9, abs = 1e-9)
  }
}
# hr2o (n, kind, which, structure 1 common 2 separate, x[n], y[n], z[n]): the other 2-d structures for regression (df is not allowed for separate)
for (rep in 1:8) {
  n <- sample(40:70, 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n, 0, 0.8); z <- sin(x) + 0.5 * y + rnorm(n, 0, 0.3)
  for (kd in 0:2) for (stt in 1:2) {
    if (kd == 1 && stt == 2) next
    r <- tryCatch(h.select(cbind(x, y), z, method = c("cv", "df", "aicc")[kd + 1], structure.2d = c("common", "separate")[stt]), error = function(e) NULL)
    if (!is.null(r) && all(is.finite(r))) for (w in 1:2) cases[[length(cases) + 1]] <- case("hr2o", c(n, kd, w - 1, stt, x, y, z), r[w], rel = 1e-9, abs = 1e-9)
  }
}
emit("sm_hsel2", "sm", list(cases))
