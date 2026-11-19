# mlogit conditional logit with alternative-specific covariates, with and without alternative-specific constants.
#   args: (n, J, k, asc 0/1, choice[n] 0-based, x[n*J*k] row-major chooser, alternative, covariate)
#   fn "coef" "se" (weighted by position), "ll"
suppressMessages({library(mlogit); library(dfidx)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-4, abs = 1e-6)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20270101)
for (rep in 1:20) {
  n <- sample(60:200, 1); J <- sample(3:5, 1); k <- sample(1:3, 1); asc <- rep %% 2
  X <- array(rnorm(n * J * k), c(n, J, k)); beta <- rnorm(k, 0, 0.8); a0 <- if (asc) c(0, rnorm(J - 1, 0, 0.4)) else rep(0, J)
  U <- sapply(1:J, function(j) a0[j] + as.vector(matrix(X[, j, ], n, k) %*% beta)) + matrix(-log(-log(runif(n * J))), n)
  ch <- apply(U, 1, which.max)
  d <- data.frame(id = rep(1:n, each = J), alt = factor(rep(1:J, n)))
  for (c in 1:k) d[[paste0("x", c)]] <- as.vector(t(X[, , c]))
  d$choice <- as.vector(t(outer(ch, 1:J, "==")))
  m <- dfidx(d, idx = c("id", "alt"))
  fm <- as.formula(paste("choice ~", paste0("x", 1:k, collapse = " + "), if (asc) "" else "| 0"))
  f <- tryCatch(mlogit(fm, m, reltol = 1e-14, tol = 1e-14, iterlim = 500), error = function(e) NULL); if (is.null(f)) next
  cf <- coef(f); cf <- if (asc) c(cf[grep("Intercept", names(cf))], cf[paste0("x", 1:k)]) else cf
  se <- sqrt(diag(vcov(f))); se <- if (asc) c(se[grep("Intercept", names(se))], se[paste0("x", 1:k)]) else se
  a <- c(n, J, k, asc, ch - 1, as.vector(aperm(X, c(3, 2, 1))))
  add("coef", a, ws(cf)); add("se", a, ws(se)); add("ll", a, as.numeric(logLik(f)))
  sh <- colMeans(fitted(f, outcome = FALSE)); cases[[length(cases) + 1]] <- case("shares", a, ws(sh), rel = 1e-5, abs = 1e-7)
  ef <- effects(f, covariate = "x1"); cases[[length(cases) + 1]] <- case("effects", a, ws(as.vector(t(ef))), rel = 1e-4, abs = 1e-6)
}
# individual-specific covariates (the multinomial logit): "mnl_coef", "mnl_se", "mnl_ll" args (n, J, q, choice[n] 0-based, Z[n*q] row-major); the coefficient order is the intercepts of alternatives 2..J, then for alternatives 2..J each covariate
for (rep in 1:15) {
  n <- sample(80:200, 1); J <- sample(3:4, 1); qq <- sample(1:2, 1)
  Z <- matrix(round(rnorm(n * qq), 3), n, qq); B <- matrix(rnorm((J - 1) * qq, 0, 0.7), qq, J - 1); a0 <- c(0, rnorm(J - 1, 0, 0.4))
  U <- sapply(1:J, function(j) a0[j] + (if (j == 1) rep(0, n) else as.vector(Z %*% matrix(B[, j - 1], qq, 1)))) + matrix(-log(-log(runif(n * J))), n)
  ch <- apply(U, 1, which.max)
  d <- data.frame(id = rep(1:n, each = J), alt = factor(rep(1:J, n)))
  for (c in 1:qq) d[[paste0("z", c)]] <- rep(Z[, c], each = J)
  d$choice <- as.vector(t(outer(ch, 1:J, "==")))
  m <- dfidx(d, idx = c("id", "alt"))
  fm <- as.formula(paste("choice ~ 0 |", paste0("z", 1:qq, collapse = " + ")))
  f <- tryCatch(mlogit(fm, m, reltol = 1e-14, tol = 1e-14, iterlim = 500), error = function(e) NULL); if (is.null(f)) next
  nm <- c(paste0("(Intercept):", 2:J), unlist(lapply(2:J, function(j) paste0("z", 1:qq, ":", j))))
  cf <- coef(f)[nm]; se <- sqrt(diag(vcov(f)))[nm]
  a <- c(n, J, qq, ch - 1, as.vector(t(Z)))
  cases[[length(cases) + 1]] <- case("mnl_coef", a, ws(cf), rel = 1e-4, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("mnl_se", a, ws(se), rel = 1e-4, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("mnl_ll", a, as.numeric(logLik(f)), rel = 1e-4, abs = 1e-6)
}
emit("mlogit", "mlogit", list(cases))
