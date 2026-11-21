# sm: the bands of sm.regression and sm.density, all args (n, h, p, x[n], y[n]) unless noted.
#   "rse1"/"rse2": se under model no.effect / linear; "rmy1"/"rmy2": model.y; "rlo1" "rup1" "rlo2" "rup2": the reference band model.y -+ 2 se;
#   "rvlo"/"rvup": the variability band estimate -+ 2 se (model none).
#   "d2se" "d2lo" "d2up": the 2-d sm.density band, args (n, h1, h2, p, q, x[n], y[n]).
suppressMessages(library(sm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20262101)
for (rep in 1:20) {
  n <- sample(15:90, 1); x <- sort(runif(n, 0, 10)); y <- round(sin(x) + rnorm(n, 0, 0.3), 4); h <- runif(1, 0.5, 1.5); pr <- runif(3, 1, 9)
  for (j in 1:3) {
    a <- c(n, h, pr[j], x, y)
    for (k in 1:2) {
      m <- if (k == 1) "no.effect" else "linear"
      r <- sm.regression(x, y, h = h, model = m, eval.points = pr[j], display = "none", test = FALSE, verbose = 0)
      add(paste0("rse", k), a, r$se); add(paste0("rmy", k), a, r$model.y)
      add(paste0("rlo", k), a, r$model.y - 2 * r$se); add(paste0("rup", k), a, r$model.y + 2 * r$se)
    }
    r <- sm.regression(x, y, h = h, eval.points = pr[j], display = "none", verbose = 0)
    add("rvlo", a, r$estimate - 2 * r$se); add("rvup", a, r$estimate + 2 * r$se)
  }
}
for (rep in 1:25) {
  n <- sample(15:90, 1); x <- round(rnorm(n, 1, 2), 4); y <- round(rnorm(n), 4)
  h1 <- runif(1, 0.2, 1); h2 <- runif(1, 0.3, 1); p <- runif(1, min(x), max(x)); q <- runif(1, min(y), max(y))
  d <- sm.density(cbind(x, y), h = c(h1, h2), eval.points = cbind(p, q), display = "none")
  a <- c(n, h1, h2, p, q, x, y)
  add("d2se", a, d$se[1, 1]); add("d2lo", a, d$lower[1, 1]); add("d2up", a, d$upper[1, 1])
}
emit("sm_band", "sm", list(cases))
