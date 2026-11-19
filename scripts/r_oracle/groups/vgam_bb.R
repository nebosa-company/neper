# VGAM vglm(cbind(y, m - y) ~ x1 + ... + xp, betabinomial): "bb" args (n, p, y[n], m[n], x[n*p] row-major without the intercept, k) k 0..p the intercept and slopes of logit mu, p + 1 the logit of rho, p + 2 the log-likelihood
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271216)
for (rep in 1:5) {
  n <- sample(40:80, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 3), n, p); m <- sample(8:30, n, TRUE)
  mu <- plogis(-0.2 + as.vector(X %*% runif(p, -0.8, 0.8))); rho <- runif(1, 0.05, 0.4); s <- (1 - rho) / rho
  y <- rbinom(n, m, rbeta(n, mu * s, (1 - mu) * s))
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- y; d$m <- m
  f <- tryCatch(vglm(as.formula(paste("cbind(y, m - y) ~", paste0("x", 1:p, collapse = " + "))), betabinomial(zero = 2), data = d, control = vglm.control(epsilon = 1e-12, maxit = 200)), error = function(e) NULL)
  if (is.null(f)) next
  cf <- coef(f); v <- c(cf[1], cf[3:(p + 2)], cf[2], as.numeric(logLik(f)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("bb", c(n, p, y, m, as.vector(t(X)), k - 1), as.numeric(v[k]), rel = 1e-3, abs = 1e-4)
}
emit("vgam_bb", "VGAM", list(cases))
