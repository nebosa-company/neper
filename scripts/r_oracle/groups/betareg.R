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
# lrtest: which 70 chi-square, 72 p-value of dropping the last mean column (p >= 3).
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
  if (p >= 3) {
    f0 <- betareg(y ~ x1, data = d, link = lk); lr <- lmtest::lrtest(f0, f)
    add2(mk(70), lr$Chisq[2], 5e-4); add2(mk(72), lr$`Pr(>Chisq)`[2], 5e-3)
  }
}
# residuals and predictions: "bres" args (n, p, link, kind, i, y, design row-major) kind 0 response 1 pearson 2 deviance 3 weighted 4 sweighted 5 quantile 6 predict response 7 link 8 precision 9 variance 10 sweighted2; i 0-based
for (rep in 1:10) {
  n <- sample(60:120, 1); k <- sample(1:2, 1); X <- matrix(rnorm(n * k), n, k); lk <- sample(c("logit", "probit", "cloglog", "loglog", "cauchit"), 1); lc <- match(lk, c("logit", "probit", "cloglog", "loglog", "cauchit")) - 1
  eta <- 0.2 + X %*% c(0.6, -0.5)[1:k]; mu <- switch(lk, logit = plogis(eta), probit = pnorm(eta), cloglog = 1 - exp(-exp(eta)), loglog = exp(-exp(-eta)), cauchit = pcauchy(eta)); phi <- runif(1, 8, 40)
  y <- rbeta(n, mu * phi, (1 - mu) * phi); y <- pmin(pmax(y, 1e-4), 1 - 1e-4)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k))); f <- betareg(y ~ ., data = d, link = lk); p <- k + 1; design <- cbind(1, X)
  types <- c("response", "pearson", "deviance", "weighted", "sweighted", "quantile", "sweighted2")
  rr <- lapply(types, function(t) residuals(f, type = t)); pr <- list(predict(f, type = "response"), predict(f, type = "link"), predict(f, type = "precision"), predict(f, type = "variance"))
  for (i in sample(n, 4)) {
    for (kd in 0:5) cases[[length(cases) + 1]] <- case("bres", c(n, p, lc, kd, i - 1, y, as.vector(t(design))), as.numeric(rr[[kd + 1]][i]), rel = 5e-3, abs = 1e-4)
    cases[[length(cases) + 1]] <- case("bres", c(n, p, lc, 10, i - 1, y, as.vector(t(design))), as.numeric(rr[[7]][i]), rel = 5e-3, abs = 1e-4)
    for (kd in 6:9) cases[[length(cases) + 1]] <- case("bres", c(n, p, lc, kd, i - 1, y, as.vector(t(design))), as.numeric(pr[[kd - 5]][i]), rel = 5e-3, abs = 1e-4)
  }
}
# variable dispersion: "fitv" args (n, p, q, link (+ 10 * precision link 0 log / 1 identity / 2 sqrt), which, y, X row-major n*p, Z row-major n*q): which 0..p-1 mean coefficient, 10 + j precision coefficient j, 30 log-likelihood
for (rep in 1:18) {
  pl <- c("log", "identity", "sqrt")[(rep - 1) %% 3 + 1]; plc <- (rep - 1) %% 3
  n <- sample(80:160, 1); k <- sample(1:2, 1); X <- matrix(rnorm(n * k), n, k); zz <- rnorm(n); lk <- sample(c("logit", "probit", "cloglog"), 1); lc <- match(lk, c("logit", "probit", "cloglog")) - 1
  eta <- 0.2 + X %*% c(0.6, -0.5)[1:k]; mu <- switch(lk, logit = plogis(eta), probit = pnorm(eta), cloglog = 1 - exp(-exp(eta))); phi <- switch(pl, log = exp(3 + 0.5 * zz), identity = pmax(25 + 8 * zz, 6), sqrt = (5 + 0.6 * zz)^2)
  y <- rbeta(n, mu * phi, (1 - mu) * phi); y <- pmin(pmax(y, 1e-4), 1 - 1e-4)
  d <- data.frame(y = y, X, zz = zz); names(d) <- c("y", paste0("x", seq_len(k)), "zz")
  f <- betareg(as.formula(paste("y ~", paste0("x", seq_len(k), collapse = " + "), "| zz")), data = d, link = lk, link.phi = pl); p <- k + 1; design <- cbind(1, X); zm <- cbind(1, zz)
  mk <- function(w) c(n, p, 2, lc + 10 * plc, w, y, as.vector(t(design)), as.vector(t(zm)))
  cf <- coef(f, model = "mean"); cp <- coef(f, model = "precision"); if (pl == "sqrt") cp <- cp * sign(cp[[1]])  # phi = u^2 is the same for u and -u
  for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("fitv", mk(j - 1), cf[[j]], rel = 3e-3, abs = 1e-4)
  for (j in 1:2) cases[[length(cases) + 1]] <- case("fitv", mk(10 + j - 1), cp[[j]], rel = 3e-3, abs = 1e-4)
  cases[[length(cases) + 1]] <- case("fitv", mk(30), as.numeric(logLik(f)), rel = 1e-6, abs = 1e-6)
  sm <- summary(f)$coefficients
  for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("fitv", mk(40 + j - 1), sm$mean[j, 2], rel = 1e-2, abs = 1e-4)
  for (j in 1:2) cases[[length(cases) + 1]] <- case("fitv", mk(60 + j - 1), sm$precision[j, 2], rel = 1e-2, abs = 1e-4)
}
emit("betareg", "betareg", list(cases))
