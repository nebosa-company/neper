# MASS: fitdistr(x, "beta" / "f", start). Args: (kind 5 beta 6 F, n, which 0 est1 1 est2 2 sd1 3 sd2 4 loglik, start1, start2, x[n])
suppressMessages(library(MASS))
cases <- list()
set.seed(20262384)
for (rep in 1:40) {
  n <- sample(60:200, 1); kd <- 5 + rep %% 2
  if (kd == 5) { x <- rbeta(n, runif(1, 1.5, 4), runif(1, 2, 8)); st <- list(shape1 = 2, shape2 = 2) } else { x <- rf(n, sample(4:10, 1), sample(6:14, 1)); st <- list(df1 = 3, df2 = 3) }
  r <- tryCatch(suppressWarnings(fitdistr(x, if (kd == 5) "beta" else "f", start = st)), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik)
  for (w in 0:4) cases[[length(cases) + 1]] <- case("fdbf", c(kd, n, w, 2, 2, x), v[w + 1], rel = if (kd == 6) (if (w == 4) 1e-4 else 2e-2) else if (w %in% 2:3) 1e-3 else 1e-5, abs = 1e-7)
}
emit("mass_fdbf", "MASS", list(cases))
