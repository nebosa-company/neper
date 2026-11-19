# RSpectra: eigs with a function operator for a general real matrix A(x) = M x (M random, applied implicitly through its rows). Args: (n, k, which 0..4, kind 0 Re 1 Im, M[n * n] column-major): weighted sums as for the dense case.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262356)
for (rep in 1:25) {
  n <- sample(8:14, 1); k <- sample(2:4, 1); M <- matrix(round(rnorm(n * n), 4), n); wh <- (rep - 1) %% 5
  ev <- eigen(M)$values; key <- switch(wh + 1, Mod(ev), Re(ev), -Re(ev), abs(Im(ev)), -abs(Im(ev))); srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-9) next
  f <- function(x, args) as.vector(M %*% x)
  o <- tryCatch(eigs(f, k, n = n, which = c("LM", "LR", "SR", "LI", "SI")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000)), error = function(e) NULL)
  if (is.null(o) || length(o$values) != k) next
  v <- o$values; a <- function(kind) c(n, k, wh, kind, as.vector(M))
  cases[[length(cases) + 1]] <- case("og", a(0), sum(Re(v) * seq_along(v)), rel = 1e-6, abs = 1e-8); cases[[length(cases) + 1]] <- case("og", a(1), sum(Im(v) * seq_along(v)), rel = 1e-6, abs = 1e-8)
}
emit("spectra_opgen", "RSpectra", list(cases))
