# robustbase: Qn, Sn and huberM.
#   args: (n, x...)   fn "qn" "sn" "hmu" "hs" "hit" (huberM location, scale and iterations at k = 1.5, tol 1e-6)
suppressMessages(library(robustbase))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
set.seed(20261222)
for (rep in 1:30) {
  n <- sample(c(2:14, 15:60), 1); x <- round(rnorm(n) * 2 + (rep %% 3 == 0) * c(rep(0, n - 2), 15, -12)[seq_len(n)], 4)
  a <- c(n, x)
  add("qn", a, Qn(x), 1e-6); add("sn", a, Sn(x))
  if (n >= 3) { t2 <- scaleTau2(x, mu.too = TRUE); add("tmu", a, t2[1]); add("tsd", a, t2[2]) }
  if (n >= 3) { h <- huberM(x); add("hmu", a, h$mu); add("hs", a, h$s); add("hit", a, h$it) }
}
emit("robustbase", "robustbase", list(cases))
