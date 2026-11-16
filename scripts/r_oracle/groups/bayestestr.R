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
emit("bayestestr", "bayestestR", list(cases))
