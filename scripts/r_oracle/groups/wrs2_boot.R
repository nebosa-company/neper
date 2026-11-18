# WRS2 yuenbt and pb2gen under set.seed. Args: (kind, seed, nx, ny, par, nboot, which, x..., y...): kind 0 yuenbt (par = trim, side TRUE), 1 yuenbt (side FALSE),
# 2 pb2gen (par 0 mom, 1 median, 2 mean); which 0 test, 1 lower limit, 2 upper limit, 3 p value, 4 difference (yuenbt only).
suppressMessages(library(WRS2))
cases <- list()
set.seed(20261801)
add <- function(args, want, rel = 1e-8, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("b", args, want, rel = rel, abs = abs)
for (rep in 1:6) {
  nx <- sample(15:30, 1); ny <- sample(15:30, 1)
  x <- round(rnorm(nx, 0, 1) + (rep %% 2) * rexp(nx), 3); y <- round(rnorm(ny, 0.5, 1.4), 3)
  d <- data.frame(v = c(x, y), g = factor(rep(c("a", "b"), c(nx, ny))))
  seed <- 100 + rep; nboot <- c(199, 299, 399)[rep %% 3 + 1]
  for (kind in 0:1) {
    set.seed(seed); r <- yuenbt(v ~ g, data = d, tr = 0.2, nboot = nboot, side = (kind == 0))
    hdr <- function(w) c(kind, seed, nx, ny, 0.2, nboot, w, x, y)
    add(hdr(0), r$test); add(hdr(1), r$conf.int[1]); add(hdr(2), r$conf.int[2]); add(hdr(3), r$p.value); add(hdr(4), r$diff)
  }
  for (est in c("mom", "median", "mean")) {
    set.seed(seed); r <- pb2gen(v ~ g, data = d, est = est, nboot = nboot)
    code <- match(est, c("mom", "median", "mean")) - 1
    hdr <- function(w) c(2, seed, nx, ny, code, nboot, w, x, y)
    add(hdr(0), r$test); add(hdr(1), r$conf.int[1]); add(hdr(2), r$conf.int[2]); add(hdr(3), r$p.value)
  }
}
emit("wrs2_boot", "WRS2", list(cases))
