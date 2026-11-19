# MASS: fitdistr(x, "t"). Args: (n, which, x[n]): which 0 m, 1 s, 2 df, 3 sd m, 4 sd s, 5 sd df, 6 loglik
# Tolerances (1e-5, standard errors of the t fit 1e-3): the t likelihood is flat in df and Nelder-Mead stops at reltol 1.5e-8, which amplifies the one-ulp exp/log/lgamma differences measured by mass_probe.R; see the ceiling note there
suppressMessages(library(MASS))
cases <- list()
set.seed(20262383)
for (rep in 1:40) {
  n <- sample(60:200, 1); x <- 1 + 2 * rt(n, df = runif(1, 3, 9))
  r <- tryCatch(suppressWarnings(fitdistr(x, "t")), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik)
  for (w in 0:6) cases[[length(cases) + 1]] <- case("fdt", c(n, w, x), v[w + 1], rel = if (w %in% 3:5) 1e-3 else 1e-5, abs = 1e-7)
}
emit("mass_fdt", "MASS", list(cases))
