# bayestestr: hdi, eti, p_direction and rope on a posterior sample.
#   "hdi" and "eti" (ci, part 0 low 1 high, n, x...); "pd" (0, 0, n, x...); "rope" (lo, hi, n, x...)
suppressMessages(library(bayestestR))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20262011)
for (rep in 1:30) {
  n <- sample(100:600, 1); x <- round(if (rep %% 3 == 0) rgamma(n, 2, 1) - 1 else rnorm(n, runif(1, -0.5, 0.5), runif(1, 0.5, 2)), 5); ci <- sample(c(0.5, 0.8, 0.89, 0.95), 1)
  h <- hdi(x, ci = ci, verbose = FALSE); e <- eti(x, ci = ci)
  add("hdi", c(ci, 0, n, x), h$CI_low); add("hdi", c(ci, 1, n, x), h$CI_high)
  add("eti", c(ci, 0, n, x), e$CI_low); add("eti", c(ci, 1, n, x), e$CI_high)
  add("pd", c(0, 0, n, x), as.numeric(p_direction(x)$pd))
  r <- sort(runif(2, -0.5, 0.5)); add("rope", c(r, n, x), as.numeric(rope(x, range = r, ci = 1)$ROPE_Percentage))
}
# rope with a ci and equivalence_test: args (ci, method 0 ETI / 1 HDI, lo, hi, n, x, j): "ropeci" j 0 percentage, 1 superiority, 2 inferiority, 3 CI low, 4 CI high; "equiv" j ignored, 0 Rejected 1 Accepted 2 Undecided
for (rep in 1:30) {
  n <- sample(100:500, 1); x <- round(rnorm(n, runif(1, -0.3, 0.3), runif(1, 0.05, 0.5)), 5); ci <- sample(c(0.5, 0.8, 0.95, 1), 1)
  r <- sort(runif(2, -0.3, 0.3)); me <- sample(c("ETI", "HDI"), 1); if (ci == 1) me <- "ETI"; mi <- as.numeric(me == "HDI")
  rp <- rope(x, range = r, ci = ci, ci_method = me, complement = TRUE, verbose = FALSE)
  vals <- c(rp$ROPE_Percentage, rp$Superiority_Percentage, rp$Inferiority_Percentage, attr(rp, "CI_bounds"))
  for (j in 0:4) add("ropeci", c(ci, mi, r, n, x, j), vals[j + 1])
  eq <- equivalence_test(x, range = r, ci = ci, ci_method = me, verbose = FALSE)
  add("equiv", c(ci, mi, r, n, x, 0), match(eq$ROPE_Equivalence, c("Rejected", "Accepted", "Undecided")) - 1)
}
emit("bayestestr", "bayestestR", list(cases))
