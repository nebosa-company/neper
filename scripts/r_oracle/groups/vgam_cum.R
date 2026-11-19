# VGAM vglm(y ~ x1 + ... + xp, cumulative(parallel = TRUE)): the proportional odds model, "cum" args (n, p, J, y[n] 0-based, x[n*p] row-major, k) k 0..J-2 intercepts, J-1..J-2+p slopes, J-1+p log-likelihood, then the standard errors in the same order
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271210)
for (rep in 1:14) {
  n <- sample(150:400, 1); p <- sample(1:3, 1); J <- sample(3:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  lat <- as.vector(X %*% runif(p, -1, 1)) + rlogis(n); br <- sort(rnorm(J - 1, 0, 0.8)); y <- as.integer(cut(lat, c(-Inf, br, Inf))) - 1
  if (length(unique(y)) < J) next
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- ordered(y)
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), cumulative(parallel = TRUE), data = d), error = function(e) NULL)
  if (is.null(f)) next
  cf <- coef(f); se <- sqrt(diag(vcov(f))); v <- c(cf, as.numeric(logLik(f)), se)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("cum", c(n, p, J, y, as.vector(t(X)), k - 1), v[k], rel = 1e-4, abs = 1e-5)
}
emit("vgam_cum", "VGAM", list(cases))
