# RSpectra: eigs (general real matrices, values and vector moduli; which LM LR SR LI SI). Args: (n, k, which 0..4, kind 0 real parts 1 imaginary parts, A[n * n] column-major): the sum of value * position. Draws where the k cut splits
# a conjugate pair, and where R's Arnoldi does not converge, are skipped.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262350)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("eg", args, want, rel = 1e-6, abs = 1e-8)
for (rep in 1:30) {
  n <- sample(7:12, 1); k <- sample(2:4, 1); A <- matrix(round(rnorm(n * n), 4), n); wh <- (rep - 1) %% 5
  ev <- eigen(A)$values
  key <- switch(wh + 1, Mod(ev), Re(ev), -Re(ev), abs(Im(ev)), -abs(Im(ev)))
  srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-9) next
  o <- tryCatch(eigs(A, k, which = c("LM", "LR", "SR", "LI", "SI")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000)), error = function(e) NULL)
  if (is.null(o) || length(o$values) != k) next
  v <- o$values; a <- function(kind) c(n, k, wh, kind, as.vector(A))
  add(a(0), sum(Re(v) * seq_along(v))); add(a(1), sum(Im(v) * seq_along(v))); add(a(2), sum(Mod(o$vectors) * seq_along(o$vectors)))
}
emit("spectra_gen", "RSpectra", list(cases))
