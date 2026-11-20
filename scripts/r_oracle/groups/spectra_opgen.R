# RSpectra: eigs with a function operator for a general real matrix A(x) = M x (M random, applied implicitly through its rows); which acts on the operator itself (SM included: R has no sigma for a function).
# Args: (n, k, which 0 LM 1 LR 2 SR 3 LI 4 SI 5 SM, part, M[n * n] column-major); part 0 values re, 1 values im, 2 phase-aligned vectors re, 3 vectors im; sums weight by position. A draw whose R answer is not the true
# k extreme eigenvalues (ARPACK's SM) is skipped, as are splits of a conjugate pair; the members of a pair are listed positive imaginary part first on both sides.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262356)
w <- function(M) sum(as.vector(M) * seq_along(M))
rot <- function(V) { V <- as.matrix(V); apply(V, 2, function(v) { j <- which.max(Mod(v)); v * Conj(v[j]) / Mod(v[j]) }) }
kf <- function(wh, z) switch(wh + 1, Mod(z), Re(z), -Re(z), abs(Im(z)), -abs(Im(z)), -Mod(z))
for (rep in 1:36) {
  n <- sample(20:30, 1); k <- sample(2:4, 1); M <- matrix(round(rnorm(n * n), 4), n); wh <- (rep - 1) %% 6
  ev <- eigen(M)$values; key <- kf(wh, ev); srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next
  f <- function(x, args) as.vector(M %*% x)
  o <- tryCatch(suppressWarnings(eigs(f, k, n = n, which = c("LM", "LR", "SR", "LI", "SI", "SM")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000))), error = function(e) NULL)
  if (is.null(o) || length(o$values) != k) next
  vv <- o$values; V <- o$vectors
  if (max(abs(sort(kf(wh, vv)) - sort(srt[1:k]))) > 1e-8) next
  for (i in seq_len(k - 1)) if (Im(vv[i]) < 0 && abs(vv[i + 1] - Conj(vv[i])) < 1e-8) { vv[c(i, i + 1)] <- vv[c(i + 1, i)]; V[, c(i, i + 1)] <- V[, c(i + 1, i)] }
  R <- rot(V); a <- function(part) c(n, k, wh, part, as.vector(M))
  for (p in 0:3) cases[[length(cases) + 1]] <- case("og", a(p), switch(p + 1, w(Re(vv)), w(Im(vv)), w(Re(R)), w(Im(R))), rel = 1e-9, abs = 1e-11)
}
emit("spectra_opgen", "RSpectra", list(cases))
