# VGAM vglm(y ~ x1 + ... + xp, sratio or cratio (link, parallel = TRUE)): "cr" args (n, p, J, lk 0 logit 1 probit 2 cloglog, vr 0 sratio 1 cratio, y[n] 0-based, x[n*p] row-major, k) k 0..J-2 intercepts, J-1..J-2+p slopes, J-1+p log-likelihood, then the standard errors in the same order
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271210)
for (rep in 1:36) {
  lkn <- c("logitlink", "probitlink", "clogloglink"); lk <- (rep - 1) %% 3; vr <- (rep - 1) %/% 3 %% 2
  n <- sample(150:400, 1); p <- sample(1:3, 1); J <- sample(3:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  lat <- as.vector(X %*% runif(p, -1, 1)) + rlogis(n); br <- sort(rnorm(J - 1, 0, 0.8)); y <- as.integer(cut(lat, c(-Inf, br, Inf))) - 1
  if (length(unique(y)) < J) next
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- ordered(y)
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), (if (vr == 0) sratio(link = lkn[lk + 1], parallel = TRUE) else cratio(link = lkn[lk + 1], parallel = TRUE)), data = d, control = vglm.control(epsilon = 1e-12, maxit = 100)), error = function(e) NULL)
  if (is.null(f)) next
  cf <- coef(f); se <- sqrt(diag(vcov(f))); v <- c(cf, as.numeric(logLik(f)), se)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("cr", c(n, p, J, lk, vr, y, as.vector(t(X)), k - 1), v[k], rel = 1e-3, abs = 1e-5)
}
emit("vgam_cr", "VGAM", list(cases))
