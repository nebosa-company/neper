# pscl zeroinfl and hurdle with Poisson counts and a logit zero part, at a tight tolerance.
#   args: (n, p, q, kind 0 zeroinfl 1 hurdle, y[n], x[n*p] row-major with constant, z[n*q] row-major with constant)
#   fn "ll" (log-likelihood), "count" (count coefficients weighted by position), "zero" (zero-part coefficients weighted by position); "secount" and "sezero" (the standard errors, sqrt of diag(vcov), weighted by position; R's Hessian is numeric so the tolerance is 2e-3)
suppressMessages(library(pscl))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-4, abs = 1e-5)
set.seed(20261210)
for (rep in 1:24) {
  n <- sample(300:600, 1); p <- sample(2:3, 1); q <- sample(1:2, 1) + 1; kind <- (rep - 1) %% 2
  x <- cbind(1, matrix(rnorm(n * (p - 1)), n)); z <- cbind(1, matrix(rnorm(n * (q - 1)), n))
  b <- c(0.4, rnorm(p - 1, 0, .4)); g <- c(-0.5, rnorm(q - 1, 0, .6))
  lam <- exp(as.vector(x %*% b)); pz <- plogis(as.vector(z %*% g))
  y <- ifelse(runif(n) < pz, 0, rpois(n, lam))
  if (kind == 1) { y <- rpois(n, lam); y[runif(n) < pz] <- 0 }
  d <- data.frame(y = y); for (j in seq_len(p - 1)) d[[paste0("x", j)]] <- x[, j + 1]; for (j in seq_len(q - 1)) d[[paste0("z", j)]] <- z[, j + 1]
  fx <- paste(c("1", if (p > 1) paste0("x", seq_len(p - 1))), collapse = " + "); fz <- paste(c("1", if (q > 1) paste0("z", seq_len(q - 1))), collapse = " + ")
  fm <- as.formula(paste("y ~", fx, "|", fz)); fm1 <- as.formula(paste("y ~", fx))
  f <- tryCatch(suppressWarnings(if (kind == 0) zeroinfl(fm, data = d, control = zeroinfl.control(reltol = 1e-14, maxit = 5000)) else hurdle(fm, data = d, control = hurdle.control(reltol = 1e-14, maxit = 5000))), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, q, kind, y, as.vector(t(x)), as.vector(t(z)))
  cc <- coef(f, "count"); zc <- coef(f, "zero")
  add("ll", a, as.numeric(logLik(f))); add("count", a, sum(cc * seq_along(cc))); add("zero", a, sum(zc * seq_along(zc)))
  if (kind == 0) { r2 <- tryCatch(suppressMessages(pR2(f)), error = function(e) NULL); if (!is.null(r2)) for (u in 1:6) cases[[length(cases) + 1]] <- case(paste0("r2", u - 1), a, unname(r2[u]), rel = 1e-4, abs = 1e-5) }
  for (ty in 0:2) { pr <- predict(f, type = c("response", "count", "zero")[ty + 1]); cases[[length(cases) + 1]] <- case(paste0("pred", ty), a, sum(pr * seq_along(pr)), rel = 1e-4, abs = 1e-6) }
  if (kind == 0) { out <- tryCatch(suppressWarnings(capture.output(vuong(f, glm(fm1, family = poisson, data = d)))), error = function(e) NULL); st <- if (is.null(out)) NULL else sapply(c("Raw", "AIC-corrected", "BIC-corrected"), function(k) as.numeric(strsplit(trimws(sub(k, "", out[startsWith(out, k)][1])), " +")[[1]][1])); if (!is.null(st) && all(is.finite(st))) for (ty in 0:2) cases[[length(cases) + 1]] <- case(paste0("vuong", ty), a, st[ty + 1], rel = 1e-5, abs = 1e-5) }
  sv <- sqrt(diag(vcov(f))); ns <- names(sv); sc <- sv[grepl("^count_", ns)]; sz <- sv[grepl("^zero_", ns)]
  cases[[length(cases) + 1]] <- case("secount", a, sum(sc * seq_along(sc)), rel = 2e-3, abs = 1e-6); cases[[length(cases) + 1]] <- case("sezero", a, sum(sz * seq_along(sz)), rel = 2e-3, abs = 1e-6)
}
emit("pscl", "pscl", list(cases))
