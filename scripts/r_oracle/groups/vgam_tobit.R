# VGAM vglm(y ~ x1 + ... + xp, tobit(Lower = lo)): "tob" args (n, p, lo, y[n], x[n*p] row-major without the intercept, k) k 0..p the intercept and slopes of the mean, p + 1 the log sd, p + 2 the log-likelihood
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271215)
for (rep in 1:12) {
  n <- sample(150:300, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 3), n, p); lo <- 0
  yl <- 0.3 + as.vector(X %*% runif(p, -1, 1)) + rnorm(n, 0, runif(1, 0.5, 1.5)); y <- pmax(yl, lo); if (mean(y == lo) < 0.05 || mean(y == lo) > 0.7) next
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- y
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), tobit(Lower = lo), data = d, control = vglm.control(epsilon = 1e-12, maxit = 200)), error = function(e) NULL)
  if (is.null(f)) next
  cf <- coef(f); v <- c(cf[1], cf[3:(p + 2)], cf[2], as.numeric(logLik(f)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("tob", c(n, p, lo, y, as.vector(t(X)), k - 1), as.numeric(v[k]), rel = 1e-4, abs = 1e-5)
}
emit("vgam_tobit", "VGAM", list(cases))
