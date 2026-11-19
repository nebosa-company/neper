# gamlss.dist BCCGo: "bd" density, "bp" distribution, "bq" quantile. Args: (mu, sigma, nu, x_or_p)
suppressMessages(library(gamlss.dist))
cases <- list()
set.seed(20262440)
for (rep in 1:60) {
  mu <- runif(1, 0.5, 8); sg <- runif(1, 0.1, 0.8); nu <- c(runif(1, -2, 2), 0, runif(1, 0.2, 3), runif(1, -3, -0.2))[rep %% 4 + 1]
  x <- qBCCGo(runif(1, 0.02, 0.98), mu, sg, nu); p <- runif(1, 0.02, 0.98)
  if (!is.finite(x) || x <= 0) next
  cases[[length(cases) + 1]] <- case("bd", c(mu, sg, nu, x), dBCCGo(x, mu, sg, nu), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("bp", c(mu, sg, nu, x), pBCCGo(x, mu, sg, nu), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("bq", c(mu, sg, nu, p), qBCCGo(p, mu, sg, nu), rel = 1e-9, abs = 1e-13)
}
emit("gamlss_bccgo", "gamlss.dist", list(cases))
