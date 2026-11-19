# VGAM vglm(y ~ x1 + ... + xp, acat(parallel = TRUE)): the adjacent categories model (loglink), "acat" args (n, p, J, y[n] 0-based, x[n*p] row-major, k) k 0..J-2 intercepts, J-1..J-2+p slopes, J-1+p log-likelihood, then the standard errors in the same order
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271210)
for (rep in 1:14) {
  n <- sample(150:400, 1); p <- sample(1:3, 1); J <- sample(3:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  lat <- as.vector(X %*% runif(p, -1, 1)) + rlogis(n); br <- sort(rnorm(J - 1, 0, 0.8)); y <- as.integer(cut(lat, c(-Inf, br, Inf))) - 1
  if (length(unique(y)) < J) next
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- ordered(y)
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), acat(parallel = TRUE), data = d, control = vglm.control(epsilon = 1e-12, maxit = 100)), error = function(e) NULL)
  if (is.null(f)) next
  cf <- coef(f); se <- sqrt(diag(vcov(f))); v <- c(cf, as.numeric(logLik(f)), se)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("acat", c(n, p, J, y, as.vector(t(X)), k - 1), v[k], rel = 1e-4, abs = 1e-6)
}
emit("vgam_acat", "VGAM", list(cases))
