# mice then with(imp, lm(y ~ x)) then pool(): Rubin's and Reiter's rules over the completed data, with the Barnard-Rubin df for the residual df, an infinite df and a given dfcom; pool.r.squared.
# args as micefull (n, p, m, maxit, seed, data[n*p] with NaN, ncat[p], meth[p], pred[p*p], nv = 0, post[2p], pas[3p]) then ycol (0-based), nx, xcols[nx] (0-based), dfcom (NaN: the residual df), rule (0 Rubin, 1 Reiter).
# "pool_imp" is the weighted sum of the imputed values as in micefull, "pool_a" the sum over coefficients c and fields f in (estimate, ubar, b, t, df, riv, lambda, fmi) of (8c + f + 1) times the value (NaN as 0),
# "pool_b" the sum over c and (std.error, statistic, p.value, conf.low, conf.high) of (5c + f + 1) times the value, "pool_r2" the sum of (i + 1) times (est, lo 95, hi 95, fmi) of pool.r.squared
suppressMessages(library(mice))
cases <- list()
set.seed(20261119)
CODE <- c(norm.nob = 0, norm = 1, norm.predict = 2, pmm = 3, norm.boot = 5)
for (rep in 1:60) {
  n <- sample(30:70, 1); p <- sample(3:4, 1); m <- sample(3:8, 1); maxit <- sample(2:3, 1)
  B <- matrix(rnorm(p * p), p, p); X <- round(matrix(rnorm(n * p), n, p) %*% B + 2, 3)
  for (j in sample(p, 2)) X[sample(n, sample(3:8, 1)), j] <- NA
  df <- as.data.frame(X)
  meth <- sample(names(CODE), p, replace = TRUE)
  ycol <- sample(p, 1); nx <- sample(1:(p - 1), 1); xc <- sort(sample(setdiff(1:p, ycol), nx))
  dfc <- c(NA, NA, Inf, sample(15:60, 1))[sample(4, 1)]
  rule <- if (rep %% 4 == 0) 1 else 0
  pm <- matrix(1, p, p); diag(pm) <- 0
  seed <- sample(1:100000, 1)
  pmeth <- meth; names(pmeth) <- names(df)
  imp <- tryCatch(suppressWarnings(mice(df, m = m, maxit = maxit, method = pmeth, predictorMatrix = pm, seed = seed, printFlag = FALSE)), error = function(e) NULL)
  if (is.null(imp) || !is.null(imp$loggedEvents)) next
  ex <- parse(text = paste0("lm(", names(df)[ycol], " ~ ", paste(names(df)[xc], collapse = " + "), ")"))[[1]]
  fit <- do.call(with, list(imp, ex))
  pl <- tryCatch(suppressWarnings(if (is.na(dfc)) pool(fit, rule = if (rule == 1) "reiter2003" else "rubin1987") else pool(fit, dfcom = dfc, rule = if (rule == 1) "reiter2003" else "rubin1987")), error = function(e) NULL)
  if (is.null(pl)) next
  sm <- summary(pl, conf.int = TRUE)
  pr <- pl$pooled
  r2 <- suppressWarnings(pool.r.squared(fit))
  flat <- c()
  for (j in seq_len(p)) if (nrow(imp$imp[[j]]) > 0) for (im in seq_len(m)) flat <- c(flat, as.numeric(imp$imp[[j]][[im]]))
  if (length(flat) == 0 || anyNA(flat)) next
  dat <- as.matrix(X); dat[is.na(dat)] <- NaN
  args <- c(n, p, m, maxit, seed, as.vector(dat), rep(0, p), CODE[meth], as.vector(t(pm)), 0, rep(NaN, 2 * p), rep(0, 3 * p), ycol - 1, nx, xc - 1, ifelse(is.na(dfc), NaN, dfc), rule)
  na0 <- function(v) ifelse(is.na(v), 0, v)
  fa <- c(); fb <- c()
  for (c in seq_len(nrow(pr))) {
    fa <- c(fa, pr$estimate[c], pr$ubar[c], pr$b[c], pr$t[c], pr$df[c], pr$riv[c], pr$lambda[c], pr$fmi[c])
    fb <- c(fb, sm$std.error[c], sm$statistic[c], sm$p.value[c], sm$conf.low[c], sm$conf.high[c])
  }
  cases[[length(cases) + 1]] <- case("pool_imp", args, sum(seq_along(flat) * flat), rel = 1e-6, abs = 1e-8)
  cases[[length(cases) + 1]] <- case("pool_a", args, sum(seq_along(fa) * na0(fa)), rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("pool_b", args, sum(seq_along(fb) * na0(fb)), rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("pool_r2", args, sum(seq_along(r2) * as.numeric(r2)), rel = 1e-9, abs = 1e-10)
}
emit("micepool", c("mice"), list(cases))
