# cramer (coda's cramer.test of the acceptance list): the Cramer two-sample statistic, the ordinary and permutation bootstrap critical values and p-values under set.seed, and the eigenvalue method.
# The package is not in the default library: its CRAN source (0.9-4) is installed with the compiled lookup-matrix routine replaced by the same sums in R; put that library first in R_ORACLE_LIB.
#   args (d, m, n, X[m * d] row-major, Y[n * d], kernel (0 Cramer, 1 Bahr, 2 Log, 3 FracA, 4 FracB), conf.level, replicates, seed)
#   fn "cr_stat" "cr_boot_crit" "cr_boot_p" "cr_perm_crit" "cr_perm_p" "cr_ev_crit" "cr_ev_p"
suppressMessages(library(cramer))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
kn <- c("phiCramer", "phiBahr", "phiLog", "phiFracA", "phiFracB")
set.seed(20261230)
for (rep in 1:20) {
  d <- sample(1:3, 1); m <- sample(8:25, 1); n <- sample(8:25, 1)
  X <- matrix(rnorm(m * d), m, d); Y <- matrix(rnorm(n * d, 0.3 * (rep %% 3), 1 + 0.4 * (rep %% 2)), n, d)
  k <- sample(0:4, 1); conf <- sample(c(0.9, 0.95), 1); R <- sample(c(100, 200, 400), 1); seed <- sample(1:1e6, 1)
  a <- c(d, m, n, as.vector(t(X)), as.vector(t(Y)), k, conf, R, seed)
  xx <- if (d == 1) as.vector(X) else X; yy <- if (d == 1) as.vector(Y) else Y
  st <- cramer.test(xx, yy, just.statistic = TRUE, kernel = kn[k + 1])$statistic; add("cr_stat", a, st)
  set.seed(seed); b <- suppressWarnings(cramer.test(xx, yy, conf.level = conf, replicates = R, sim = "ordinary", kernel = kn[k + 1])); add("cr_boot_crit", a, b$crit.value); add("cr_boot_p", a, b$p.value)
  set.seed(seed); b <- suppressWarnings(cramer.test(xx, yy, conf.level = conf, replicates = R, sim = "permutation", kernel = kn[k + 1])); add("cr_perm_crit", a, b$crit.value); add("cr_perm_p", a, b$p.value)
  e <- suppressWarnings(cramer.test(xx, yy, conf.level = conf, sim = "eigenvalue", kernel = kn[k + 1])); add("cr_ev_crit", a, e$crit.value, 1e-7); add("cr_ev_p", a, e$p.value, 1e-7)
}
emit("cramer", "cramer", list(cases))
