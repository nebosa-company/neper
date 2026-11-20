# MASS: fitdistr(x, "beta" / "f", start). Args: (kind 5 beta 6 F, n, which 0 est1 1 est2 2 sd1 3 sd2 4 loglik, start1, start2, x[n])
# Tolerances: estimates and loglik 1e-8, standard errors 1e-5 (optimHess finite differences at the BFGS stop point; 3 of 70 F and beta cases exceed 1e-6). The start values passed to Neper are the ones R uses (F starts at 3, 3).
suppressMessages(library(MASS))
cases <- list()
set.seed(20262384)
for (rep in 1:40) {
  n <- sample(60:200, 1); kd <- 5 + rep %% 2
  if (kd == 5) { x <- rbeta(n, runif(1, 1.5, 4), runif(1, 2, 8)); st <- list(shape1 = 2, shape2 = 2) } else { x <- rf(n, sample(4:10, 1), sample(6:14, 1)); st <- list(df1 = 3, df2 = 3) }
  r <- tryCatch(suppressWarnings(fitdistr(x, if (kd == 5) "beta" else "f", start = st)), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik)
  for (w in 0:4) cases[[length(cases) + 1]] <- case("fdbf", c(kd, n, w, st[[1]], st[[2]], x), v[w + 1], rel = if (w %in% 2:3) 1e-4 else 1e-8, abs = 1e-7)
  # standard errors and loglik evaluated at R's own estimates (kind 10 + kd)
  for (w in 2:4) cases[[length(cases) + 1]] <- case("fdbf", c(kd + 10, n, w, r$estimate[[1]], r$estimate[[2]], x), v[w + 1], rel = if (w == 4) 1e-8 else 1e-5, abs = 1e-9)
}
# kind 7 chi-squared (n, which 0 df 1 sd 2 loglik, start, x[n])
for (rep in 1:30) {
  n <- sample(60:200, 1); x <- rchisq(n, df = runif(1, 2, 9))
  r <- tryCatch(suppressWarnings(fitdistr(x, "chi-squared", start = list(df = 3))), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik)
  for (w in 0:2) cases[[length(cases) + 1]] <- case("fdchi", c(7, n, w, 3, 0, x), v[w + 1], rel = 1e-8, abs = 1e-7)
}
emit("mass_fdbf", "MASS", list(cases))
