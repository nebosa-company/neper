# sm: hnorm, sm.density (1-d and 2-d) and sm.regression at evaluation points.
#   args: "hn1"/"hn2" (n, x...); "dens1" (n, h, p, x...); "dens2" (n, h1, h2, p, q, x..., y...); "reg" (n, h, p, poly, x..., y...)
suppressMessages(library(sm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20262001)
for (rep in 1:20) {
  n <- sample(15:90, 1); x <- round(rnorm(n, 1, 2), 4); y <- round(rnorm(n), 4)
  add("hn1", c(n, x), hnorm(x)); add("hn2", c(n, x), hnorm(cbind(x, y))[1])
  h <- runif(1, 0.2, 1); pts <- runif(3, min(x), max(x))
  for (p in pts) add("dens1", c(n, h, p, x), sm.density(x, h = h, eval.points = p, display = "none")$estimate)
  h2 <- runif(1, 0.3, 1); q <- runif(2, min(y), max(y)); p2 <- runif(2, min(x), max(x))
  d2 <- sm.density(cbind(x, y), h = c(h, h2), eval.points = cbind(p2, q), display = "none")$estimate
  add("dens2", c(n, h, h2, p2[1], q[1], x, y), d2[1, 1]); add("dens2", c(n, h, h2, p2[2], q[2], x, y), d2[2, 2])
  xs <- sort(runif(n, 0, 10)); ys <- round(sin(xs) + rnorm(n, 0, 0.3), 4); hr <- runif(1, 0.5, 1.5); pr <- runif(3, 1, 9)
  for (po in 0:1) { r <- sm.regression(xs, ys, h = hr, eval.points = pr, poly.index = po, display = "none")$estimate; for (j in 1:3) add("reg", c(n, hr, pr[j], po, xs, ys), r[j]) }
}
emit("sm", "sm", list(cases))
