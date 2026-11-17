# ResourceSelection beyond hoslem.test: rsf, rspf, rsf.null, simulateUsedAvail, the numbers of mep and kdepairs (the panel calls).
#   rsf / rspf: fn "r" args (kind, n, pc, m, B, seed, useinits, q, y[n], X[n * pc] column-major with the intercept, inits[pc], mvec[n or 1]);
#     kind 0 rsf, 1 rspf logit, 2 rspf cloglog, 3 rspf probit; pe = pc - (kind == 0); q 0 loglik, 1 converged, 2 + j coef, 2 + pe + j se,
#     2 + 2 pe + j the sum over b of (b + 1) times bootstrap column b (B > 0), 2 + 3 pe the sum of the fitted values, 2 + 3 pe + 1 their index-weighted sum. The length of mvec is 1 (m) or n (match ids).
#   rsf.null: fn "z" args (n, m, y[n]); q = loglik
#   simulateUsedAvail: fn "s" args (seed, S, pc, n_used, m, link, parms[pc + 1], data[S * pc], [weighted]) the sum of the rows drawn; a trailing 1 their index-weighted sum, 2 the used draws only, 3 the available draws only
#   mep: fn "m" args (type, link, n, nbin, minbucket, digits, level, q, x[n], y[n]); q 0 levels, 1 link, 2 sum of x, 3 its level-weighted sum, 3 + c sum of quantile column c, 6 + c its level-weighted sum
#   kdepairs panels: fn "k" args (n, m, q, x1[m], x2[m]); q 0 cor, 1 sum of the kde2d grid, 2 its index-weighted sum (index i + n j), 3 / 4 the same for the lowess y, 5 + i the grid cell [i, n + 1 - i]
suppressMessages(library(ResourceSelection))
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
links <- c("logit", "cloglog", "probit")
design <- function(S, nu, m, seed) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(S), x2 = rnorm(S))
  th <- c(-1, runif(1, 0.3, 1), runif(1, -0.8, 0.8))
  simulateUsedAvail(d, th, nu, m)
}
for (rep in 1:8) {
  kind <- (rep - 1) %% 4; nu <- sample(20:28, 1); m <- sample(2:4, 1); B <- sample(c(0, 10, 20), 1); seed <- sample(1:1e6, 1)
  d <- design(120, nu, m, rep + 100)
  mvec <- 0
  if (rep %% 3 == 0) { id <- c(1:nu, rep(1:nu, each = m)); perm <- sample(length(id)); d <- d[perm, ]; mvec <- id[perm] } else if (rep %% 3 == 1) mvec <- m
  X <- model.matrix(~ x1 + x2, d); n <- nrow(X); pc <- ncol(X)
  useinits <- rep %% 2; inits <- if (useinits) c(runif(1, -1, 1), runif(2, -0.5, 0.5)) else rep(0, pc)
  set.seed(seed)
  f <- tryCatch(suppressWarnings(
    if (kind == 0) { if (useinits) rsf(status ~ x1 + x2, d, m = mvec, B = B, inits = inits) else rsf(status ~ x1 + x2, d, m = mvec, B = B) }
    else { if (useinits) rspf(status ~ x1 + x2, d, m = mvec, B = B, link = links[kind], inits = inits) else rspf(status ~ x1 + x2, d, m = mvec, B = B, link = links[kind]) }),
    error = function(e) NULL)
  if (is.null(f)) next
  pe <- length(f$coefficients)
  a <- c(kind, n, pc, if (length(mvec) == 1) mvec else 0, B, seed, useinits, 0, d$status, X, inits, mvec)
  tol <- if (useinits) 1e-8 else 1e-5
  put <- function(q, v) { a2 <- a; a2[8] <- q; add("r", a2, v, rel = tol, abs = tol * 1e-2) }
  put(0, f$loglik); put(1, as.numeric(f$converged))
  for (j in seq_len(pe)) { put(2 + j - 1, f$coefficients[j]); if (!is.na(f$std.error[j])) put(2 + pe + j - 1, f$std.error[j]) }
  if (B > 0) for (j in seq_len(pe)) put(2 + 2 * pe + j - 1, sum((1:(B + 1)) * f$bootstrap[j, ]))
  put(2 + 3 * pe, sum(f$fitted.values)); put(2 + 3 * pe + 1, sum(f$fitted.values * seq_len(n)))
}
for (rep in 1:3) {
  d <- design(100, 30, 4, 500 + rep)
  y <- d$status
  for (mm in c(0, 4)) {
    nn <- tryCatch(suppressWarnings(rsf.null(y, m = mm)), error = function(e) NULL)
    if (is.null(nn)) next
    add("z", c(length(y), mm, y), nn$loglik, rel = 1e-9, abs = 1e-9)
  }
}
for (rep in 1:10) {
  S <- if (rep > 6) 300 else sample(20:80, 1); nu <- sample(10:60, 1); m <- sample(1:3, 1); link <- sample(0:2, 1); seed <- sample(1:1e6, 1)
  d <- data.frame(x1 = rnorm(S), x2 = rbinom(S, 2, 0.5)); parms <- c(runif(1, -1, 0.5), runif(2, -0.5, 0.5))
  set.seed(seed)
  s <- simulateUsedAvail(d, parms, nu, m, link = links[link + 1])
  ids <- match(s$x1, d$x1)
  add("s", c(seed, S, 2, nu, m, link, parms, d$x1, d$x2), sum(ids), rel = 0, abs = 0)
  add("s", c(seed, S, 2, nu, m, link, parms, d$x1, d$x2, 1), sum(ids * seq_along(ids)), rel = 0, abs = 0)
  add("s", c(seed, S, 2, nu, m, link, parms, d$x1, d$x2, 2), sum(ids[1:nu]), rel = 0, abs = 0)
  add("s", c(seed, S, 2, nu, m, link, parms, d$x1, d$x2, 3), sum(ids[-(1:nu)]), rel = 0, abs = 0)
}
codes <- c(logit = 0, cloglog = 1, probit = 2, log = 3, identity = 4)
for (rep in 1:14) {
  type <- c("numeric", "unique", "factor")[(rep - 1) %% 3 + 1]
  n <- sample(60:150, 1)
  x <- if (type == "numeric") rnorm(n) else if (type == "unique") round(rnorm(n), 1) else sample(1:5, n, TRUE)
  y <- if (rep %% 4 == 0) rnorm(n) else if (rep %% 4 == 1) plogis(rnorm(n)) else rexp(n)
  nbin <- sample(5:12, 1); mb <- sample(3:7, 1); lv <- sample(c(0.9, 0.95), 1)
  lk <- if (rep %% 5 == 0) "probit" else NULL
  if (!is.null(lk)) y <- plogis(rnorm(n))
  xin <- if (type == "factor") factor(x) else x
  res <- tryCatch(suppressWarnings(ResourceSelection:::.mep(xin, y, level = lv, link = lk, type = type, n = nbin, minbucket = mb, digits = 1, plot = FALSE)), error = function(e) NULL)
  if (is.null(res)) next
  L <- length(res$x)
  base <- c(match(type, c("numeric", "unique", "factor")) - 1, if (is.null(lk)) -1 else codes[[lk]], n, nbin, mb, 1, lv)
  xv <- if (type == "factor") as.numeric(as.character(res$x)) else as.numeric(res$x)
  put <- function(q, v) add("m", c(base, q, x, y), v)
  put(0, L); put(1, codes[[res$link]]); put(2, sum(xv)); put(3, sum(xv * seq_len(L)))
  for (cc in 1:3) { put(3 + cc, sum(res$y[, cc])); put(6 + cc, sum(res$y[, cc] * seq_len(L))) }
}
for (rep in 1:4) {
  m <- sample(40:90, 1); x1 <- rnorm(m); x2 <- 0.5 * x1 + rnorm(m); n <- 25
  kd <- MASS::kde2d(x1, x2, n = n); lo <- lowess(x1, x2)
  put <- function(q, v) add("k", c(n, m, q, x1, x2), v)
  put(0, cor(x1, x2))
  put(1, sum(kd$z)); put(2, sum(kd$z * seq_along(kd$z))); put(3, sum(lo$y)); put(4, sum(lo$y * seq_along(lo$y)))
  for (i in c(1, 7, 13, 25)) put(5 + i, kd$z[i, 26 - i])
}
emit("hoslem_rsf", c("ResourceSelection", "MASS"), list(cases))
