# irlba::prcomp_irlba: sdev, totalvar and |rotation| (position-weighted), with centring and scaling. R's irlba stops at tol 1e-5, so 1e-4. Args: (m, n, k, scale, kind 0 sdev 1 totalvar 2 |rotation|, x[m * n] row-major).
suppressMessages(library(irlba))
cases <- list()
set.seed(20262352)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pc", args, want, rel = 1e-4, abs = 1e-6)
for (rep in 1:16) {
  m <- sample(40:80, 1); n <- sample(12:20, 1); k <- sample(2:4, 1); sc <- rep %% 2; X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  r <- tryCatch(suppressWarnings(prcomp_irlba(X, n = k, center = TRUE, scale. = sc == 1)), error = function(e) NULL); if (is.null(r)) next
  a <- function(kind) c(m, n, k, sc, kind, as.vector(t(X)))
  add(a(0), sum(r$sdev * seq_along(r$sdev))); add(a(1), r$totalvar); add(a(2), sum(abs(r$rotation) * seq_along(r$rotation)))
}
emit("spectra_prcomp", "irlba", list(cases))
