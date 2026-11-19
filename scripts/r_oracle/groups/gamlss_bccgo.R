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
# ST3C (the compiled-code twin of ST3): "s3d", "s3p", "s3q" with args (mu, sigma, nu, tau, x_or_p)
for (rep in 1:40) {
  mu <- rnorm(1, 1, 2); sg <- runif(1, 0.3, 2); nu <- runif(1, 0.4, 2.5); tau <- runif(1, 2.5, 30); x <- rnorm(1, mu, 2 * sg); p <- runif(1, 0.02, 0.98)
  cases[[length(cases) + 1]] <- case("s3d", c(mu, sg, nu, tau, x), dST3C(x, mu, sg, nu, tau), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("s3p", c(mu, sg, nu, tau, x), pST3C(x, mu, sg, nu, tau), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("s3q", c(mu, sg, nu, tau, p), qST3C(p, mu, sg, nu, tau), rel = 1e-8, abs = 1e-10)
}
emit("gamlss_bccgo", "gamlss.dist", list(cases))
