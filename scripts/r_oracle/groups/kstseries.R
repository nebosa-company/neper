# KernSmooth bkde, dpik; tseries jarque.bera.test, runs.test.
#   bkde: (kernel 0 normal 1 box 2 epanech 3 biweight 4 triweight, bandwidth (0 default), gridsize, n, x..., stat)
#     fn "bkde_x", "bkde_y": stat 0 first, 1 last, 2 sum, 3 position-weighted sum (from 1), 4 length
#   dpik: (n, x...)   jb: (n, x...) -> "jb_stat" "jb_p"   runs: (n, bits...) -> "runs_stat" "runs_p"
library(KernSmooth); library(tseries)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261115)
stats5 <- function(v) c(v[1], v[length(v)], sum(v), sum(seq_along(v) * v), length(v))
kn <- c("normal", "box", "epanech", "biweight", "triweight")
xs <- list(round(rnorm(40), 3), round(rexp(60) * 2, 3), round(c(rnorm(30), rnorm(30, 4)), 3), round(runif(25, -3, 7), 2))
for (x in xs) {
  for (k in 0:4) for (bw in c(0, 0.4)) for (m in c(51, 401)) {
    r <- tryCatch(suppressWarnings(if (bw > 0) bkde(x, kn[k + 1], bandwidth = bw, gridsize = m) else bkde(x, kn[k + 1], gridsize = m)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(k, bw, m, length(x), x)
    sx <- stats5(r$x); sy <- stats5(r$y)
    for (j in 0:4) { add("bkde_x", c(a, j), sx[j + 1]); add("bkde_y", c(a, j), sy[j + 1]) }
  }
  add("dpik", c(length(x), x), dpik(x))
  jb <- jarque.bera.test(x); add("jb_stat", c(length(x), x), unname(jb$statistic)); add("jb_p", c(length(x), x), jb$p.value)
}
for (k in 1:12) {
  bits <- rbinom(20 + k, 1, 0.3 + 0.04 * k); if (length(unique(bits)) < 2) next
  rt <- runs.test(factor(bits, levels = 0:1)); a <- c(length(bits), bits)
  add("runs_stat", a, unname(rt$statistic)); add("runs_p", a, rt$p.value)
}
emit("kstseries", c("KernSmooth", "tseries"), list(cases))
