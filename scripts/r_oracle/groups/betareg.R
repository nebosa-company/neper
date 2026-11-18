# betareg: logit-link beta regression with constant precision: coefficients, precision and log-likelihood.
#   args: (n, p, which, y[n]..., x row-major n by p with the intercept column...)   fn "fit"
#   which: 0.. a coefficient, 20 the precision phi, 30 the log-likelihood.  Agreement is to the optimiser tolerance, so the tolerances are looser.
suppressMessages(library(betareg))
cases <- list()
add <- function(args, want, rel) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("fit", args, want, rel = rel, abs = 1e-4)
set.seed(20261211)
for (rep in 1:10) {
  n <- sample(40:120, 1); k <- sample(1:3, 1)
  X <- matrix(rnorm(n * k), n, k)
  mu <- plogis(0.2 + X %*% c(0.8, -0.6, 0.4)[1:k]); phi <- runif(1, 5, 40)
  y <- rbeta(n, mu * phi, (1 - mu) * phi); y <- pmin(pmax(y, 1e-4), 1 - 1e-4)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k)))
  f <- betareg(y ~ ., data = d)
  p <- k + 1; design <- cbind(1, X)
  mk <- function(w) c(n, p, w, y, as.vector(t(design)))
  cf <- coef(f, model = "mean")
  for (j in seq_len(p)) add(mk(j - 1), cf[[j]], 1e-3)
  add(mk(20), coef(f, model = "precision")[[1]], 1e-3)
  add(mk(30), as.numeric(logLik(f)), 1e-6)
}
# links and standard errors: "fitl" args (n, p, link 0 logit / 1 probit / 2 cloglog / 3 loglog / 4 cauchit, which, y, design row-major): which 0..p-1 coefficient, 20 precision, 30 log-likelihood, 40 + j the standard error of coefficient j, 60 the standard error of phi
add2 <- function(args, want, rel) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("fitl", args, want, rel = rel, abs = 1e-4)
for (rep in 1:12) {
  n <- sample(60:150, 1); k <- sample(1:2, 1); X <- matrix(rnorm(n * k), n, k); lk <- sample(c("logit", "probit", "cloglog", "loglog", "cauchit"), 1); lc <- match(lk, c("logit", "probit", "cloglog", "loglog", "cauchit")) - 1
  eta <- 0.2 + X %*% c(0.6, -0.5)[1:k]; mu <- switch(lk, logit = plogis(eta), probit = pnorm(eta), cloglog = 1 - exp(-exp(eta)), loglog = exp(-exp(-eta)), cauchit = pcauchy(eta)); phi <- runif(1, 8, 40)
  y <- rbeta(n, mu * phi, (1 - mu) * phi); y <- pmin(pmax(y, 1e-4), 1 - 1e-4)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k)))
  f <- betareg(y ~ ., data = d, link = lk); p <- k + 1; design <- cbind(1, X); sm <- summary(f)$coefficients
  mk <- function(w) c(n, p, lc, w, y, as.vector(t(design)))
  cf <- coef(f, model = "mean")
  for (j in seq_len(p)) add2(mk(j - 1), cf[[j]], 2e-3)
  add2(mk(20), coef(f, model = "precision")[[1]], 2e-3); add2(mk(30), as.numeric(logLik(f)), 1e-6)
  for (j in seq_len(p)) add2(mk(40 + j - 1), sm$mean[j, 2], 5e-3)
  add2(mk(60), sm$precision[1, 2], 5e-3)
}
# residuals and predictions: "bres" args (n, p, link, kind, i, y, design row-major) kind 0 response 1 pearson 2 deviance 3 weighted 4 sweighted 5 quantile 6 predict response 7 link 8 precision 9 variance; i 0-based
for (rep in 1:10) {
  n <- sample(60:120, 1); k <- sample(1:2, 1); X <- matrix(rnorm(n * k), n, k); lk <- sample(c("logit", "probit", "cloglog", "loglog", "cauchit"), 1); lc <- match(lk, c("logit", "probit", "cloglog", "loglog", "cauchit")) - 1
  eta <- 0.2 + X %*% c(0.6, -0.5)[1:k]; mu <- switch(lk, logit = plogis(eta), probit = pnorm(eta), cloglog = 1 - exp(-exp(eta)), loglog = exp(-exp(-eta)), cauchit = pcauchy(eta)); phi <- runif(1, 8, 40)
  y <- rbeta(n, mu * phi, (1 - mu) * phi); y <- pmin(pmax(y, 1e-4), 1 - 1e-4)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k))); f <- betareg(y ~ ., data = d, link = lk); p <- k + 1; design <- cbind(1, X)
  types <- c("response", "pearson", "deviance", "weighted", "sweighted", "quantile")
  rr <- lapply(types, function(t) residuals(f, type = t)); pr <- list(predict(f, type = "response"), predict(f, type = "link"), predict(f, type = "precision"), predict(f, type = "variance"))
  for (i in sample(n, 4)) {
    for (kd in 0:5) cases[[length(cases) + 1]] <- case("bres", c(n, p, lc, kd, i - 1, y, as.vector(t(design))), as.numeric(rr[[kd + 1]][i]), rel = 5e-3, abs = 1e-4)
    for (kd in 6:9) cases[[length(cases) + 1]] <- case("bres", c(n, p, lc, kd, i - 1, y, as.vector(t(design))), as.numeric(pr[[kd - 5]][i]), rel = 5e-3, abs = 1e-4)
  }
}
emit("betareg", "betareg", list(cases))
