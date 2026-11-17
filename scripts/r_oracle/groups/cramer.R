# cramer (the Cramer two-sample test, source tarball cramer_0.9-4 from CRAN, its one Rcpp function replaced by the same loop in R; set CRAMER_SRC to R/cramer.R).
#   args: (m, n, d, kernel 0 phiCramer 1 phiBahr 2 phiLog 3 phiFracA 4 phiFracB, replicates, seed, x then y rows)
#   "cr_stat" statistic; "cr_op" / "cr_oc" p.value / crit.value of sim = "ordinary" after set.seed(seed); "cr_pp" / "cr_pc" the same for "permutation"; "cr_ep" / "cr_ec" sim = "eigenvalue"
suppressMessages(library(boot))
calculateLookupMatrix <- function(length, daten, lookup) { for (i in 2:length) for (j in 1:(i - 1)) { v <- sum((daten[i, ] - daten[j, ])^2); lookup[i, j] <- v; lookup[j, i] <- v }; lookup }
assign("calculateLookupMatrix", calculateLookupMatrix, envir = globalenv())
src <- Sys.getenv("CRAMER_SRC", "D:/Temp/claude/src/cramer/cramer/R/cramer.R")
exprs <- parse(src); for (e in exprs) if (!(is.call(e) && identical(e[[1]], as.name("require")))) eval(e, globalenv())
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
kn <- c("phiCramer", "phiBahr", "phiLog", "phiFracA", "phiFracB")
set.seed(20261501)
for (rep in 1:25) {
  m <- sample(5:12, 1); n <- sample(5:12, 1); d <- sample(1:2, 1); ki <- sample(0:4, 1); R <- 200
  x <- matrix(rnorm(m * d), m); y <- matrix(rnorm(n * d, 0.4 * (rep %% 3), 1 + 0.3 * (rep %% 2)), n); seed <- sample(1:100000, 1)
  a <- c(m, n, d, ki, R, seed, as.vector(t(x)), as.vector(t(y))); xx <- if (d == 1) as.vector(x) else x; yy <- if (d == 1) as.vector(y) else y
  add("cr_stat", a, cramer.test(xx, yy, just.statistic = TRUE, kernel = kn[ki + 1])$statistic)
  if (rep <= 12) {
    set.seed(seed); r1 <- cramer.test(xx, yy, replicates = R, sim = "ordinary", kernel = kn[ki + 1]); add("cr_op", a, r1$p.value); add("cr_oc", a, r1$crit.value)
    set.seed(seed); r2 <- cramer.test(xx, yy, replicates = R, sim = "permutation", kernel = kn[ki + 1]); add("cr_pp", a, r2$p.value); add("cr_pc", a, r2$crit.value)
  }
  r3 <- suppressWarnings(cramer.test(xx, yy, sim = "eigenvalue", kernel = kn[ki + 1])); add("cr_ep", a, r3$p.value, 1e-7); add("cr_ec", a, r3$crit.value, 1e-7)
}
emit("cramer", c("boot"), list(cases))
