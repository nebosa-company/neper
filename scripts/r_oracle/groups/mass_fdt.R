# MASS: fitdistr(x, "t"). Args: (n, which, x[n]): which 0 m, 1 s, 2 df, 3 sd m, 4 sd s, 5 sd df, 6 loglik
# Args (n, which, m, s, df, x[n]); which 10 + k evaluates k at the given estimates. Tolerances of the fitted values (estimates 1e-5, standard errors 1e-3, loglik 1e-8; the at-estimate cases 1e-8): the t likelihood is flat in df and Nelder-Mead stops at reltol 1.5e-8, which amplifies the one-ulp exp/log/lgamma differences measured by mass_probe.R; see the ceiling note there
suppressMessages(library(MASS))
cases <- list()
set.seed(20262383)
for (rep in 1:40) {
  n <- sample(60:200, 1); x <- 1 + 2 * rt(n, df = runif(1, 3, 9))
  r <- tryCatch(suppressWarnings(fitdistr(x, "t")), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik)
  e <- r$estimate
  for (w in 0:6) cases[[length(cases) + 1]] <- case("fdt", c(n, w, 0, 0, 0, x), v[w + 1], rel = if (w == 6) 1e-8 else if (w >= 3) 1e-3 else 1e-5, abs = 1e-7)
  # the standard errors and loglik evaluated at R's own estimates: loglik 1e-8, sd m 1e-6, sd s and sd df 1e-3 (the df direction is flat, so optimHess differences of 1e-3 step amplify one-ulp density differences; measured max 2.4e-4)
  for (w in 3:6) cases[[length(cases) + 1]] <- case("fdt", c(n, w + 10, e[1], e[2], e[3], x), v[w + 1], rel = if (w == 3) 1e-6 else if (w == 6) 1e-8 else 1e-3, abs = 1e-9)
}
emit("mass_fdt", "MASS", list(cases))
