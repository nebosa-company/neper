# RSpectra svds, eigs_sym and eigs on sparse Matrix inputs (triplets, 0-based). Args: (kind 0 svds 1 eigs_sym 2 eigs general, m, n, k, nnz, which, sigma, part, i[nnz], j[nnz], x[nnz]);
# which as the dense groups (eigs_sym 0 LM 1 LA 2 SA 3 SM 4 sigma 5 BE; eigs 0 LM 1 LR 2 SR 3 LI 4 SI 6 sigma). part 0 values, 1 vectors (sign-aligned for kinds 0 and 1: u and v for svds as part 1 and 2;
# phase-aligned real and imaginary parts as parts 1 and 2 for kind 2, with the conjugate pair listed positive imaginary part first). Sums weight by position.
suppressMessages({library(RSpectra); library(Matrix)})
cases <- list()
set.seed(20262353)
w <- function(M) sum(as.vector(M) * seq_along(M))
rot <- function(V) { V <- as.matrix(V); apply(V, 2, function(v) { j <- which.max(Mod(v)); v * Conj(v[j]) / Mod(v[j]) }) }
add <- function(kind, m, n, k, A, wh, sg, part, want) { s <- summary(A); cases[[length(cases) + 1]] <<- case("sps", c(kind, m, n, k, nrow(s), wh, sg, part, s$i - 1, s$j - 1, s$x), want, rel = 1e-9, abs = 1e-11) }
rv <- function(x) round(rnorm(x), 4)
op <- list(tol = 1e-14, maxitr = 5000)
for (rep in 1:30) {
  kind <- (rep - 1) %% 3
  if (kind == 0) {
    m <- sample(30:60, 1); n <- sample(15:30, 1); k <- sample(2:4, 1); A <- rsparsematrix(m, n, density = 0.25, rand.x = rv)
    sv <- svd(as.matrix(A))$d; if (abs(sv[k] - sv[k + 1]) < 1e-6) next
    o <- svds(A, k, opts = op); s <- apply(o$u, 2, function(x) sign(x[which.max(abs(x))]))
    add(0, m, n, k, A, 0, 0, 0, w(o$d)); add(0, m, n, k, A, 0, 0, 1, w(t(t(o$u) * s))); add(0, m, n, k, A, 0, 0, 2, w(t(t(o$v) * s)))
  } else if (kind == 1) {
    n <- sample(20:40, 1); k <- sample(2:4, 1); wh <- sample(c(0:5), 1); sg <- round(runif(1, -1, 1), 3); A0 <- rsparsematrix(n, n, density = 0.3, rand.x = rv)
    A <- as(crossprod(A0) - Diagonal(n, 0.1), "generalMatrix"); ev <- eigen(as.matrix(A), symmetric = TRUE)$values
    key <- switch(wh + 1, abs(ev), ev, -ev, -abs(ev), -abs(ev - sg), ev)
    if (wh != 5) { srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next }
    o <- tryCatch(if (wh == 4) eigs_sym(A, k, sigma = sg, opts = op) else eigs_sym(A, k, which = c("LM", "LA", "SA", "SM", NA, "BE")[wh + 1], opts = op), error = function(e) NULL)
    if (is.null(o) || length(o$values) != k) next
    V <- apply(o$vectors, 2, function(v) v * sign(v[which.max(abs(v))]))
    add(1, n, n, k, A, wh, sg, 0, w(o$values)); add(1, n, n, k, A, wh, sg, 1, w(V))
  } else {
    n <- sample(20:40, 1); k <- sample(2:4, 1); wh <- c(0, 1, 2, 3, 4, 6)[sample(6, 1)]; sg <- round(runif(1, -1, 1), 3); A <- rsparsematrix(n, n, density = 0.3, rand.x = rv)
    ev <- eigen(as.matrix(A))$values; key <- switch(wh + 1, Mod(ev), Re(ev), -Re(ev), abs(Im(ev)), -abs(Im(ev)), NULL, -Mod(ev - sg))
    srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next
    o <- tryCatch(suppressWarnings(if (wh == 6) eigs(A, k, sigma = sg, opts = op) else eigs(A, k, which = c("LM", "LR", "SR", "LI", "SI")[wh + 1], opts = op)), error = function(e) NULL)
    if (is.null(o) || length(o$values) != k) next
    vv <- o$values; V <- o$vectors
    for (i in seq_len(k - 1)) if (Im(vv[i]) < 0 && abs(vv[i + 1] - Conj(vv[i])) < 1e-8) { vv[c(i, i + 1)] <- vv[c(i + 1, i)]; V[, c(i, i + 1)] <- V[, c(i + 1, i)] }
    R <- rot(V)
    add(2, n, n, k, A, wh, sg, 0, w(Re(vv)) + 1000 * w(Im(vv))); add(2, n, n, k, A, wh, sg, 1, w(Re(R))); add(2, n, n, k, A, wh, sg, 2, w(Im(R)))
  }
}
emit("spectra_sparse", c("RSpectra", "Matrix"), list(cases))
