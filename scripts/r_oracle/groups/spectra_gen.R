# RSpectra eigs on general real matrices: values and complex eigenvectors (phase-aligned: the largest-modulus component real positive, ARPACK fixes no phase).
#   args: (n, k, which 0 LM 1 LR 2 SR 3 LI 4 SI 5 SM 6 sigma, sigma, part, cplx, Re(A)[n * n] column-major, then Im(A)[n * n] when cplx = 1); part 0 values re, 1 values im, 2 vectors re, 3 vectors im (sum of value * column-major position).
# R lists the two members of a conjugate pair in either order (it depends on the restarts): both sides list the positive imaginary part first.
# Draws where the k cut splits a conjugate pair or ties, and where R's Arnoldi does not converge, are skipped.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262350)
# reps with dflt = TRUE run R at its default tol (1e-10, maxitr 300): R's own stopping error is then part of the answer, so values are compared to 1e-8 and vectors to 1e-6.
add <- function(args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case("eg", args, want, rel = rel, abs = abs)
w <- function(M) sum(as.vector(M) * seq_along(M))
rot <- function(V) { V <- as.matrix(V); apply(V, 2, function(v) { j <- which.max(Mod(v)); v * Conj(v[j]) / Mod(v[j]) }) }
# reps 29-35 hand R a complex matrix: RSpectra discards the imaginary part with a warning, so the answer is that of Re(A); args carry both parts and Neper's eigs_complex takes both.
for (rep in 1:70) {
  n <- sample(20:30, 1); k <- sample(2:4, 1); A <- matrix(round(rnorm(n * n), 4), n); wh <- c(0, 1, 2, 3, 4, 5, 6)[(rep - 1) %% 7 + 1]; dflt <- rep > 56; sg <- round(runif(1, -1, 1), 3)
  ev <- eigen(A)$values
  key <- switch(wh + 1, Mod(ev), Re(ev), -Re(ev), abs(Im(ev)), -abs(Im(ev)), -Mod(ev), -Mod(ev - sg))
  srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next
  Ain <- if (rep %in% 29:35) A + 1i * matrix(round(rnorm(n * n), 4), n) else A
  ropts <- if (dflt) list() else list(tol = 1e-14, maxitr = 5000)
  o <- tryCatch(suppressWarnings(if (wh == 6) eigs(Ain, k, sigma = sg, opts = ropts) else eigs(Ain, k, which = c("LM", "LR", "SR", "LI", "SI", "SM")[wh + 1], opts = ropts)), error = function(e) NULL)
  if (is.null(o) || length(o$values) != k) next
  # R's regular-mode SM on a general matrix (Spectra's smallest-magnitude Arnoldi) often reports converged values that are not the smallest ones; only draws where R is right are kept (the rest depend on its restart path)
  if (wh == 5 && max(abs(sort(Mod(o$values)) - sort(Mod(ev))[1:k])) > 1e-6) { message("SM wrong in R: rep ", rep); next }
  vv <- o$values; V <- o$vectors
  for (i in seq_len(k - 1)) if (Im(vv[i]) < 0 && abs(vv[i + 1] - Conj(vv[i])) < 1e-8) { vv[c(i, i + 1)] <- vv[c(i + 1, i)]; V[, c(i, i + 1)] <- V[, c(i + 1, i)] }
  o$values <- vv; R <- rot(V); cp <- rep %in% 29:35; a <- function(part) c(n, k, wh, sg, part, as.integer(cp), as.vector(Re(Ain)), if (cp) as.vector(Im(Ain)))
  rv <- if (dflt) 1e-8 else 1e-9; rc <- if (dflt) 1e-6 else 1e-9; ac <- if (dflt) 1e-8 else 1e-11
  add(a(0), w(Re(o$values)), rv, ac); add(a(1), w(Im(o$values)), rv, ac); add(a(2), w(Re(R)), rc, ac); add(a(3), w(Im(R)), rc, ac)
}
emit("spectra_gen", "RSpectra", list(cases))
