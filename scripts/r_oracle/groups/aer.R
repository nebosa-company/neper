# AER: ivreg with its summary and diagnostics, dispersiontest.
#   fn "iv": args (n, p, q, intercept, which, endo[p], y[n], x[n*p] row-major, z[n*q] row-major); x is (intercept, exogenous columns, endogenous columns),
#      z is (intercept, the same exogenous columns, the excluded instruments). which: 0 coef 1 se (position-weighted sums) 2 sigma 3 R2 4 adj R2 5 Wald F 6 Wald p
#      and 10 + 4 * row + col of the diagnostics table (rows: weak instruments per endogenous, Wu-Hausman, Sargan; cols: df1 df2 statistic p)
#   fn "disp": args (n, p, trafo, alt, which, y[n], x[n*p] row-major); which 0 z 1 p 2 estimate; trafo 0 is the default test, alt 0 greater 1 two.sided 2 less
suppressMessages({library(AER)})
cases <- list()
ws <- function(v) sum(v * seq_along(v))
set.seed(20261121)
for (rep in 1:8) {
  n <- sample(35:55, 1); ne <- sample(1:2, 1); nx <- sample(0:2, 1); ni <- ne + sample(0:2, 1)
  ex <- matrix(rnorm(n * nx), n); iz <- matrix(rnorm(n * ni), n); u <- rnorm(n)
  en <- sapply(seq_len(ne), function(j) as.vector(iz %*% runif(ni, 0.4, 1)) + 0.7 * u + rnorm(n))
  en <- matrix(en, n)
  y <- 1 + (if (nx) as.vector(ex %*% rnorm(nx)) else 0) + as.vector(en %*% rnorm(ne)) + u + rnorm(n)
  ex <- round(ex, 4); iz <- round(iz, 4); en <- round(en, 4); y <- round(y, 4)
  d <- data.frame(y = y); X <- cbind(1, ex, en); Z <- cbind(1, ex, iz)
  colnames(X) <- c("c", if (nx) paste0("e", 1:nx), paste0("n", 1:ne)); colnames(Z) <- c("c", if (nx) paste0("e", 1:nx), paste0("i", 1:ni))
  dd <- data.frame(y = y, X[, -1, drop = FALSE], Z[, grep("^i", colnames(Z)), drop = FALSE])
  f1 <- as.formula(paste("y ~", paste(colnames(X)[-1], collapse = " + ")))
  f2 <- as.formula(paste("~", paste(colnames(Z)[-1], collapse = " + ")))
  m <- ivreg(f1, f2, data = dd); s <- summary(m, diagnostics = TRUE)
  p <- ncol(X); q <- ncol(Z); endo <- c(rep(0, 1 + nx), rep(1, ne))
  add <- function(which, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("iv", c(n, p, q, 1, which, endo, y, as.vector(t(X)), as.vector(t(Z))), want, rel = rel, abs = 1e-11)
  add(0, ws(coef(m))); add(1, ws(s$coefficients[, 2])); add(2, s$sigma); add(3, s$r.squared); add(4, s$adj.r.squared)
  add(5, s$waldtest[1]); add(6, s$waldtest[2], 1e-8)
  dg <- s$diagnostics
  for (r in seq_len(nrow(dg))) for (cc in 1:4) {
    v <- dg[r, cc]
    if (is.na(v) && !(cc == 1)) next
    add(10 + 4 * (r - 1) + (cc - 1), v, if (cc == 4) 1e-8 else 1e-9)
  }
}
for (rep in 1:4) {
  n <- sample(50:80, 1); p <- sample(1:2, 1)
  x <- round(matrix(rnorm(n * p), n), 3); b <- runif(p, -0.5, 0.5)
  mu <- exp(0.5 + as.vector(x %*% b)); y <- rnbinom(n, mu = mu, size = sample(c(2, 8, 100), 1))
  X <- cbind(1, x); dd <- data.frame(y = y, x); g <- glm(y ~ ., family = poisson, data = dd)
  for (alt in c("greater", "two.sided", "less")) for (tr in list(NULL, 1, 2)) {
    dt <- if (is.null(tr)) dispersiontest(g, alternative = alt) else dispersiontest(g, trafo = tr, alternative = alt)
    a <- c(n, p + 1, if (is.null(tr)) 0 else tr, match(alt, c("greater", "two.sided", "less")) - 1)
    for (w in 0:2) cases[[length(cases) + 1]] <- case("disp", c(a, w, y, as.vector(t(X))), c(dt$statistic, dt$p.value, dt$estimate)[w + 1], rel = if (w == 1) 1e-8 else 1e-9, abs = 1e-12)
  }
}
emit("aer", "AER", list(cases))
