# MASS: gamma.shape of a Gamma glm. Args: (n, deviance, df.residual, y[n], fitted[n], prior.weights[n], stat 0 alpha 1 SE)
suppressMessages(library(MASS))
cases <- list()
set.seed(20262381)
for (rep in 1:40) {
  n <- sample(30:120, 1); x <- runif(n); shape <- runif(1, 1, 8); mu <- exp(0.5 + 1.2 * x)
  y <- rgamma(n, shape = shape, rate = shape / mu); w <- if (rep %% 2 == 0) round(runif(n, 0.5, 3), 2) else rep(1, n)
  f <- tryCatch(suppressWarnings(glm(y ~ x, family = Gamma(link = "log"), weights = w)), error = function(e) NULL)
  if (is.null(f)) next
  g <- tryCatch(suppressWarnings(gamma.shape(f)), error = function(e) NULL)
  if (is.null(g)) next
  a <- c(n, f$deviance, f$df.residual, y, f$fitted.values, f$prior.weights)
  cases[[length(cases) + 1]] <- case("gs", c(a, 0), g$alpha, rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("gs", c(a, 1), g$SE, rel = 1e-9, abs = 1e-10)
}
emit("mass_gshape", "MASS", list(cases))
