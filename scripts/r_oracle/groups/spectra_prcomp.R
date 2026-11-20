# irlba::prcomp_irlba under set.seed with R's default tol (1e-5): the exact port reproduces R's iterates, so sdev, totalvar and the sign-exact rotation agree to 1e-9, not just to the 1e-5 stopping tolerance.
# Args: (m, n, k, scale, seed, kind 0 sdev 1 totalvar 2 rotation, x[m * n] column-major).
suppressMessages(library(irlba))
cases <- list()
set.seed(20262352)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pc", args, want, rel = 1e-9, abs = 1e-11)
for (rep in 1:16) {
  m <- sample(40:80, 1); n <- sample(12:20, 1); k <- sample(2:4, 1); sc <- rep %% 2; X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  sd1 <- sample(1:100000, 1); set.seed(sd1)
  r <- tryCatch(suppressWarnings(prcomp_irlba(X, n = k, center = TRUE, scale. = sc == 1)), error = function(e) NULL); if (is.null(r)) next
  a <- function(kind) c(m, n, k, sc, sd1, kind, as.vector(X))
  add(a(0), sum(r$sdev * seq_along(r$sdev))); add(a(1), r$totalvar); add(a(2), sum(r$rotation * seq_along(r$rotation)))
}
emit("spectra_prcomp", "irlba", list(cases))
