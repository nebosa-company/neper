# ggm: partial correlations and the Gaussian graph fits.
#   "pcor"  args (p, nu, u[nu] 1-based, S[p*p] row-major)            -> pcor(u, S)
#   "parcor" args (p, S[p*p], i, j)                                   -> parcor(S)[i, j] (0-based)
#   "pctest" args (r, q, n, which 0 tval 1 df 2 pvalue)
#   "dag" / "con" / "cov" args (p, n, S[p*p], A[p*p], q): q 0..p*p-1 Shat row-major; dag then p Dhat, dev, df, p*p Ahat;
#         con and cov then dev, df, it
suppressMessages(library(ggm))
cases <- list()
set.seed(20261116)
rowm <- function(M) as.vector(t(M))
rndS <- function(p, n) { x <- matrix(rnorm(n * p), n, p) %*% chol(crossprod(matrix(rnorm(p * p), p, p)) + diag(p)); S <- crossprod(scale(x, scale = FALSE)) / n; dimnames(S) <- list(letters[1:p], letters[1:p]); S }
for (rep in 1:20) {
  p <- sample(3:6, 1); n <- sample(30:100, 1); S <- rndS(p, n)
  nu <- sample(2:p, 1); u <- sample(p, nu)
  cases[[length(cases) + 1]] <- case("pcor", c(p, nu, u, rowm(S)), pcor(u, S), rel = 1e-9, abs = 1e-11)
  P <- parcor(S)
  for (i in 1:p) for (j in 1:p) cases[[length(cases) + 1]] <- case("parcor", c(p, rowm(S), i - 1, j - 1), P[i, j], rel = 1e-9, abs = 1e-11)
  r <- round(runif(1, -0.9, 0.9), 3); q <- sample(0:3, 1); nn <- sample(10:60, 1); t <- pcor.test(r, q, nn)
  cases[[length(cases) + 1]] <- case("pctest", c(r, q, nn, 0), t$tval, rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("pctest", c(r, q, nn, 1), t$df, rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("pctest", c(r, q, nn, 2), t$pvalue, rel = 1e-9, abs = 1e-13)
}
for (rep in 1:20) {
  p <- sample(3:6, 1); n <- sample(40:120, 1)
  A <- matrix(0, p, p); for (i in 1:(p - 1)) for (j in (i + 1):p) A[i, j] <- rbinom(1, 1, 0.5)
  dimnames(A) <- list(letters[1:p], letters[1:p])
  # data from the DAG so the fit is not degenerate
  x <- matrix(0, n, p); for (j in 1:p) { x[, j] <- rnorm(n); for (i in which(A[, j] == 1)) x[, j] <- x[, j] + 0.6 * x[, i] }
  S <- crossprod(scale(x, scale = FALSE)) / n; dimnames(S) <- list(letters[1:p], letters[1:p])
  f <- fitDag(A, S, n)
  out <- c(rowm(f$Shat), f$Dhat, f$dev, f$df, rowm(f$Ahat))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("dag", c(p, n, rowm(S), rowm(A), q - 1), out[q], rel = 1e-8, abs = 1e-10)
}
for (rep in 1:20) {
  p <- sample(3:6, 1); n <- sample(40:120, 1); S <- rndS(p, n)
  A <- matrix(0, p, p); for (i in 1:(p - 1)) for (j in (i + 1):p) { e <- rbinom(1, 1, 0.5); A[i, j] <- e; A[j, i] <- e }
  if (all(A == 0)) { A[1, 2] <- 1; A[2, 1] <- 1 }
  if (all(A[upper.tri(A)] == 1)) { A[1, p] <- 0; A[p, 1] <- 0 }
  dimnames(A) <- list(letters[1:p], letters[1:p])
  f <- fitConGraph(A, S, n)
  out <- c(rowm(f$Shat), f$dev, f$df, f$it)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("con", c(p, n, rowm(S), rowm(A), q - 1), out[q], rel = 1e-6, abs = 1e-8)
  f <- tryCatch(fitCovGraph(A, S, n), error = function(e) NULL)
  if (!is.null(f)) { out <- c(rowm(f$Shat), f$dev, f$df, f$it); for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("cov", c(p, n, rowm(S), rowm(A), q - 1), out[q], rel = 1e-6, abs = 1e-8) }
}
# dSep ("dsep": args (p, A[p*p], nf, first, ns, second, nc, cond, 0) 1-based sets, answer 0/1) and marg.param ("mp": args (r, lev[r], types[r] as character codes, which 0 C 1 M 2 G, q) q 0 rows 1 cols 2 sum 3 weighted sum)
for (rep in 1:150) {
  p <- sample(4:8, 1); A <- matrix(0, p, p); for (i in 1:(p - 1)) for (j in (i + 1):p) A[i, j] <- rbinom(1, 1, 0.4)
  perm <- sample(p); A <- A[order(perm), order(perm)]; dimnames(A) <- list(letters[1:p], letters[1:p])
  nodes <- sample(p); nf <- sample(1:2, 1); ns <- sample(1:2, 1); nc <- sample(0:min(3, p - nf - ns), 1)
  f <- nodes[1:nf]; s <- nodes[nf + 1:ns]; cnd <- if (nc > 0) nodes[nf + ns + 1:nc] else integer(0)
  v <- dSep(A, letters[f], letters[s], if (nc > 0) letters[cnd] else c())
  cases[[length(cases) + 1]] <- case("dsep", c(p, rowm(A), nf, f, ns, s, nc, cnd, 0), as.numeric(v), rel = 0, abs = 0)
}
for (rep in 1:30) {
  r <- sample(2:3, 1); lev <- sample(2:3, r, TRUE); typ <- sample(c("l", "g", "c", "r"), r, TRUE)
  mp <- marg.param(lev, typ)
  for (w in 1:3) { M <- mp[[w]]; M <- as.matrix(M); v <- as.vector(t(M))
    out <- c(nrow(M), ncol(M), sum(v), sum(seq_along(v) * v))
    for (q in 1:4) cases[[length(cases) + 1]] <- case("mp", c(r, lev, utf8ToInt(paste(typ, collapse = "")), w - 1, q - 1), out[q], rel = 1e-9, abs = 1e-9) }
}
# fitAncestralGraph ("ag": args (p, n, S[p*p], mag[p*p], q); q 0..p*p-1 Shat, then dev, df, it, sum Bhat, sum Ohat, sum Lhat)
for (rep in 1:60) {
  p0 <- sample(5:7, 1); A <- matrix(0, p0, p0); for (i in 1:(p0 - 1)) for (j in (i + 1):p0) A[i, j] <- rbinom(1, 1, 0.45)
  dimnames(A) <- list(letters[1:p0], letters[1:p0])
  nm <- sample(0:2, 1); nc <- sample(0:1, 1); pick <- sample(p0, nm + nc)
  M <- if (nm > 0) letters[pick[1:nm]] else c(); C <- if (nc > 0) letters[pick[nm + 1]] else c()
  mag <- tryCatch(suppressWarnings(MAG(A, M, C, showmat = FALSE)), error = function(e) NULL)
  if (is.null(mag) || nrow(mag) < 3) next
  p <- nrow(mag); n <- sample(60:150, 1)
  x <- matrix(rnorm(n * p0), n, p0); for (j in 1:p0) for (i in which(A[, j] == 1)) x[, j] <- x[, j] + 0.5 * x[, i]
  S0 <- crossprod(scale(x, scale = FALSE)) / n; dimnames(S0) <- list(letters[1:p0], letters[1:p0]); S <- S0[rownames(mag), rownames(mag)]
  f <- tryCatch(suppressWarnings(fitAncestralGraph(mag, S, n)), error = function(e) NULL)
  if (is.null(f)) next
  out <- c(rowm(f$Shat), f$dev, f$df, f$it, sum(f$Bhat), sum(f$Ohat), sum(f$Lhat))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("ag", c(p, n, rowm(S), rowm(mag), q - 1), out[q], rel = 1e-6, abs = 1e-8)
}
emit("ggm", "ggm", list(cases))
