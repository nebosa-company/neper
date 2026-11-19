# VGAM vglm(y ~ x1 + ... + xp, cumulative(link, parallel = FALSE)): "cnp" args (n, p, J, lk 0 logit 1 probit 2 cloglog, y[n] 0-based, x[n*p] row-major, k) with k the index of the log-likelihood in the output (the coefficients come first, then it, then the standard errors); only the log-likelihood is compared, because R stops short of the optimum on the slopes and its standard errors differ by a few percent
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271212)
for (rep in 1:30) {
  lkn <- c("logitlink", "probitlink", "clogloglink"); lk <- (rep - 1) %% 3
  n <- sample(250:500, 1); p <- sample(1:2, 1); J <- sample(3:4, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  lat <- as.vector(X %*% runif(p, -1, 1)) + rlogis(n); br <- sort(rnorm(J - 1, 0, 0.8)); y <- as.integer(cut(lat, c(-Inf, br, Inf))) - 1
  if (length(unique(y)) < J) next
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- ordered(y)
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), cumulative(link = lkn[lk + 1], parallel = FALSE), data = d, control = vglm.control(epsilon = 1e-13, maxit = 200)), error = function(e) NULL)
  if (is.null(f) || any(!is.finite(coef(f))) || !is.finite(as.numeric(logLik(f)))) next
  cf <- as.vector(t(matrix(coef(f), nrow = J - 1))); se <- as.vector(t(matrix(sqrt(diag(vcov(f))), nrow = J - 1)))
  v <- as.numeric(logLik(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("cnp", c(n, p, J, lk, y, as.vector(t(X)), (J - 1) * (p + 1)), v[k], rel = 1e-3, abs = 1e-3)
}
emit("vgam_cum_np", "VGAM", list(cases))
