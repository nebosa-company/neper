# mixtools: boot.se (normalmixEM, regmixEM, mvnormalmixEM, multmixEM fits, seeded) and the helpers perm, wquantile, wkde, ddirichlet, rnormmix.
#   bn   args: (sel, idx, seed, k, arbvar, B, n, x[n], lambda[k], mu[k], sigma[k or 1])           the fit starts from the given values, then boot.se is seeded
#   br   args: (sel, idx, seed, k, arbvar, B, n, q, x[n x q row-major], y[n], lambda[k], beta[p x k row-major], sigma[k or 1])
#   bv   args: (sel, idx, seed, k, arbvar, B, n, p, x[n x p row-major], lambda[k], mu[k x p], sigma[nb x p x p])
#   bm   args: (sel, idx, seed, k, B, n, p, y[n x p row-major], lambda[k], theta[k x p row-major])
#        sel 1 lambda.se[idx], 2 mu.se (beta.se, theta.se) [idx], 3 sigma.se[idx], 4 sum of lambda.bs[idx, ], 5 sum of mu.bs[idx, ], 6 sum of sigma.bs[idx, ]
#   perm   args: (r, n, row, col, v[n])          (col 0: the number of rows)
#   wq     args: (prob, n, x[n], wt[n])
#   wk     args: (sym, u, bw, n, x[n], w[n])
#   dd     args: (d, x[d], alpha[d])
#   rn     args: (seed, n, m, idx, lambda[m], mu[m], sigma[m])
suppressMessages(library(mixtools))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
quiet <- function(e) { r <- NULL; capture.output(r <- try(suppressWarnings(e), silent = TRUE)); r }
rows <- function(m) as.vector(t(m))
emit_boot <- function(fn, hd, bs, se2) {
  a <- function(sel, idx, want) add(fn, c(sel, idx, hd), want)
  for (i in seq_along(bs$lambda.se)) { a(1, i, bs$lambda.se[i]); a(4, i, sum(bs$lambda[i, ])) }
  s2 <- as.vector(se2); b2 <- if (!is.null(bs$mu)) bs$mu else if (!is.null(bs$beta)) bs$beta else bs$theta
  for (i in seq_along(s2)) { a(2, i, s2[i]); a(5, i, sum(b2[i, ])) }
  if (!is.null(bs$sigma.se)) { s3 <- unlist(lapply(if (is.list(bs$sigma.se)) bs$sigma.se else list(bs$sigma.se), as.vector)); for (i in seq_along(s3)) { a(3, i, s3[i]); a(6, i, sum(bs$sigma[i, ])) } }
}
set.seed(20261501)
for (rep in 1:4) {                              # normalmixEM
  k <- 2; n <- sample(80:150, 1); mus <- c(-2, 2) + rnorm(2, 0, 0.3); x <- round(c(rnorm(n %/% 2, mus[1], 1), rnorm(n - n %/% 2, mus[2], 1.3)), 4)
  for (av in c(1, 0)) {
    st <- list(lam = c(0.5, 0.5), mu = as.numeric(quantile(x, c(0.25, 0.75))), sg = if (av) rep(sd(x) / 2, 2) else sd(x) / 2)
    fit <- quiet(normalmixEM(x, lambda = st$lam, mu = st$mu, sigma = st$sg, k = k, arbvar = as.logical(av)))
    set.seed(700 + rep); bs <- quiet(boot.se(fit, B = 10, arbvar = as.logical(av)))
    if (inherits(bs, "try-error")) next
    emit_boot("bn", c(700 + rep, k, av, 10, n, x, st$lam, st$mu, st$sg), bs, bs$mu.se)
  }
}
for (rep in 1:3) {                              # regmixEM
  k <- 2; n <- sample(70:120, 1); q <- sample(1:2, 1); xx <- matrix(round(runif(n * q, -2, 2), 3), n, q)
  comp <- rbinom(n, 1, 0.5) + 1; b <- matrix(c(-2, 2, 1, -1, 0.5, 1), q + 1, k)[, 1:k]
  y <- round(b[1, comp] + rowSums(xx * t(b[2:(q + 1), comp, drop = FALSE])) + rnorm(n, 0, 0.5), 4)
  be <- matrix(c(-1.5, 1.5, 0.5, -0.5, 0.2, 0.7)[1:((q + 1) * k)], q + 1, k)
  for (av in c(1, 0)) {
    sg <- if (av) c(1, 1) else 1
    fit <- quiet(regmixEM(y, xx, lambda = c(0.5, 0.5), beta = be, sigma = sg, k = k, arbvar = as.logical(av)))
    set.seed(800 + rep); bs <- quiet(boot.se(fit, B = 8, arbvar = as.logical(av)))
    if (inherits(bs, "try-error")) next
    emit_boot("br", c(800 + rep, k, av, 8, n, q, rows(xx), y, c(0.5, 0.5), rows(be), sg), bs, bs$beta.se)
  }
}
for (rep in 1:3) {                              # mvnormalmixEM
  k <- 2; p <- 2; n <- sample(60:90, 1); comp <- rbinom(n, 1, 0.5) + 1
  x <- round(cbind(rnorm(n, c(-2, 2)[comp], 1), rnorm(n, c(1, -1)[comp], 1.2)) + 0.3 * rnorm(n), 4)
  q <- order(rowMeans(x)); b1 <- x[q[1:(n %/% 2)], ]; b2 <- x[q[(n %/% 2 + 1):n], ]
  mu <- rows(rbind(colMeans(b1), colMeans(b2)))
  for (av in c(1, 0)) {
    sg <- if (av) c(rows(cov(b1)), rows(cov(b2))) else rows(cov(x))
    mul <- list(mu[1:2], mu[3:4]); sgl <- if (av) list(cov(b1), cov(b2)) else cov(x)
    fit <- quiet(mvnormalmixEM(x, lambda = c(0.5, 0.5), mu = mul, sigma = sgl, k = k, arbvar = as.logical(av)))
    set.seed(900 + rep); bs <- quiet(boot.se(fit, B = 6, arbvar = as.logical(av)))
    if (inherits(bs, "try-error")) next
    emit_boot("bv", c(900 + rep, k, av, 6, n, p, rows(x), c(0.5, 0.5), mu, sg), bs, unlist(bs$mu.se))
  }
}
for (rep in 1:3) {                              # multmixEM
  k <- 2; p <- 4; n <- sample(50:90, 1); th <- matrix(c(0.5, 0.2, 0.2, 0.1, 0.1, 0.2, 0.3, 0.4), k, p, byrow = TRUE)
  comp <- rbinom(n, 1, 0.5) + 1; y <- t(sapply(comp, function(cc) rmultinom(1, 30, th[cc, ])))
  th0 <- matrix(c(0.4, 0.3, 0.2, 0.1, 0.15, 0.2, 0.3, 0.35), k, p, byrow = TRUE)
  fit <- quiet(multmixEM(y, lambda = c(0.5, 0.5), theta = th0, k = k))
  set.seed(1000 + rep); bs <- quiet(boot.se(fit, B = 10))
  if (inherits(bs, "try-error")) next
  hd <- c(1000 + rep, k, 10, n, p, rows(y), c(0.5, 0.5), rows(th0))
  a <- function(sel, idx, want) add("bm", c(sel, idx, hd), want)
  for (i in seq_len(k)) { a(1, i, bs$lambda.se[i]); a(4, i, sum(bs$lambda[i, ])) }
  s2 <- as.vector(bs$theta.se); for (i in seq_along(s2)) { a(2, i, s2[i]); a(5, i, sum(bs$theta[i, ])) }
}
for (n in 1:5) for (r in 1:n) for (rep in 1:2) {   # perm
  v <- if (rep == 1) seq_len(n) else round(runif(n, 0, 10), 3); pm <- perm(n, r, v)
  add("perm", c(r, n, 0, 0, v), nrow(pm), rel = 0)
  for (i in sample(nrow(pm), min(nrow(pm), 6))) for (cc in seq_len(r)) add("perm", c(r, n, i, cc, v), pm[i, cc], rel = 0)
}
set.seed(20261502)
for (rep in 1:10) {                             # wquantile, wkde, ddirichlet, rnormmix
  n <- sample(5:40, 1); x <- round(rnorm(n), 4); wt <- runif(n)
  for (pr in c(0.1, 0.25, 0.5, 0.9)) add("wq", c(pr, n, x, wt), wquantile(wt, x, pr))
  u <- rnorm(1); bw <- runif(1, 0.2, 1)
  add("wk", c(0, u, bw, n, x, wt), wkde(x, u, wt, bw)); add("wk", c(1, u, bw, n, x, wt), wkde(x, u, wt, bw, sym = TRUE))
  d <- sample(2:5, 1); al <- runif(d, 0.5, 4); xd <- as.numeric(rdirichlet <- { g <- rgamma(d, al); g / sum(g) })
  add("dd", c(d, xd, al), ddirichlet(xd, al))
  m <- sample(2:4, 1); lam <- runif(m); lam <- lam / sum(lam); mu <- rnorm(m, 0, 3); sg <- runif(m, 0.5, 2); nn <- sample(5:30, 1)
  set.seed(1100 + rep); r <- rnormmix(nn, lam, mu, sg)
  for (i in c(1, nn %/% 2, nn)) add("rn", c(1100 + rep, nn, m, i, lam, mu, sg), r[i])
}

emit("mixtools_boot", "mixtools", list(cases))
