# RSpectra eigs on general real matrices: values and complex eigenvectors (phase-aligned: the largest-modulus component real positive, ARPACK fixes no phase).
#   args: (n, k, which 0 LM 1 LR 2 SR 3 LI 4 SI 6 sigma, sigma, part, A[n * n] column-major); part 0 values re, 1 values im, 2 vectors re, 3 vectors im (sum of value * column-major position).
# R lists the two members of a conjugate pair in either order (it depends on the restarts): both sides list the positive imaginary part first.
# Draws where the k cut splits a conjugate pair or ties, and where R's Arnoldi does not converge, are skipped.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262350)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("eg", args, want, rel = 1e-9, abs = 1e-11)
w <- function(M) sum(as.vector(M) * seq_along(M))
rot <- function(V) { V <- as.matrix(V); apply(V, 2, function(v) { j <- which.max(Mod(v)); v * Conj(v[j]) / Mod(v[j]) }) }
# reps 43-48 hand R a complex matrix: RSpectra discards the imaginary part with a warning, so the answer is that of Re(A), which is what args carry.
for (rep in 1:48) {
  n <- sample(20:30, 1); k <- sample(2:4, 1); A <- matrix(round(rnorm(n * n), 4), n); wh <- c(0, 1, 2, 3, 4, 6)[(rep - 1) %% 6 + 1]; sg <- round(runif(1, -1, 1), 3)
  ev <- eigen(A)$values
  key <- switch(wh + 1, Mod(ev), Re(ev), -Re(ev), abs(Im(ev)), -abs(Im(ev)), -Mod(ev), -Mod(ev - sg))
  srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next
  Ain <- if (rep > 42) A + 1i * matrix(round(rnorm(n * n), 4), n) else A
  o <- tryCatch(suppressWarnings(if (wh == 6) eigs(Ain, k, sigma = sg, opts = list(tol = 1e-14, maxitr = 5000)) else eigs(Ain, k, which = c("LM", "LR", "SR", "LI", "SI", "SM")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000))), error = function(e) NULL)
  if (is.null(o) || length(o$values) != k) next
  vv <- o$values; V <- o$vectors
  for (i in seq_len(k - 1)) if (Im(vv[i]) < 0 && abs(vv[i + 1] - Conj(vv[i])) < 1e-8) { vv[c(i, i + 1)] <- vv[c(i + 1, i)]; V[, c(i, i + 1)] <- V[, c(i + 1, i)] }
  o$values <- vv; R <- rot(V); a <- function(part) c(n, k, wh, sg, part, as.vector(A))
  add(a(0), w(Re(o$values))); add(a(1), w(Im(o$values))); add(a(2), w(Re(R))); add(a(3), w(Im(R)))
}
emit("spectra_gen", "RSpectra", list(cases))
