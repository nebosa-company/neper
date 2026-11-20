# RSpectra::eigs_sym and eigs through the Lanczos / Arnoldi iteration with R's start vector (opts$initvec), Krylov size (opts$ncv) and tolerance 1e-14, on matrices larger than ncv so that the iteration restarts.
#   args: (kind 0 symmetric 1 general, n, k, which, ncv, part, v0[n], A[n * n] column-major); which 0 LM 1 LA (LR) 2 SA (SR) 3 LI 4 SI 5 BE (symmetric);
#   part 0 values re, 1 values im, 2 vectors re, 3 vectors im; vectors are rotated so the largest-modulus component is real positive (ARPACK's own phase is arbitrary), all sums weight by position (column-major).
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262601)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ks", args, want, rel = 1e-9, abs = 1e-11)
w <- function(M) sum(as.vector(M) * seq_along(M))
rot <- function(V) { V <- as.matrix(V); apply(V, 2, function(v) { j <- which.max(Mod(v)); v * Conj(v[j]) / Mod(v[j]) }) }
for (rep in 1:30) {
  kind <- rep %% 2; n <- sample(20:30, 1); k <- sample(2:4, 1); ncv <- sample((k + 3):(k + 9), 1)
  A <- matrix(round(rnorm(n * n), 4), n); v0 <- round(runif(n, -0.5, 0.5), 4)
  if (kind == 0) { A <- (A + t(A)) / 2; wh <- c(0, 1, 2, 5)[sample(4, 1)]; nm <- c("LM", "LA", "SA", NA, NA, "BE")[wh + 1]
    ev <- eigen(A, symmetric = TRUE)$values; key <- switch(nm, LM = abs(ev), LA = ev, SA = -ev, BE = NULL)
    if (!is.null(key)) { srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next }
    o <- tryCatch(eigs_sym(A, k, which = nm, opts = list(ncv = ncv, tol = 1e-14, maxitr = 5000, initvec = v0)), error = function(e) NULL)
  } else { wh <- sample(0:4, 1); nm <- c("LM", "LR", "SR", "LI", "SI")[wh + 1]
    ev <- eigen(A)$values; key <- switch(nm, LM = Mod(ev), LR = Re(ev), SR = -Re(ev), LI = abs(Im(ev)), SI = -abs(Im(ev)))
    srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next
    o <- tryCatch(eigs(A, k, which = nm, opts = list(ncv = ncv, tol = 1e-14, maxitr = 5000, initvec = v0)), error = function(e) NULL)
  }
  if (is.null(o) || length(o$values) != k) next
  if (kind == 1 && any(Im(o$values) != 0)) { p <- which(Im(o$values) > 0); if (length(p) != sum(Im(o$values) < 0)) next }
  a <- function(part) c(kind, n, k, wh, ncv, part, v0, as.vector(A)); R <- rot(o$vectors)
  add(a(0), w(Re(o$values))); add(a(1), w(Im(o$values))); add(a(2), w(Re(R))); add(a(3), w(Im(R)))
}
emit("arpack", "RSpectra", list(cases))
