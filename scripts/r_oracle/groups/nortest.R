# nortest and moments. args: (n, x..., p1, p2, p3) per fn; every fn answers one number.
#   moment: (n, x, order, central, absolute)  skew kurt jb_stat jb_p
#   agostino_skew/_z/_p, anscombe_kurt/_z/_p, bonett_tau/_z/_p: (n, x, alternative 0 two.sided 1 less 2 greater)
#   lillie_d lillie_p cvm_w cvm_p sf_w sf_p: (n, x)   pearson_p pearson_pv: (n, x, classes (0 default), adjust)
suppressMessages({library(nortest); library(moments)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261115)
xs <- list(round(rnorm(30), 3), round(rexp(40), 3), round(runif(25, -2, 5), 3), round(rt(60, 4), 3), round(rnorm(150), 3), round(rlnorm(20), 3), round(c(rnorm(40), rnorm(40, 3)), 3))
alt <- c("two.sided", "less", "greater")
for (x in xs) {
  a <- c(length(x), x)
  for (ord in c(2, 3, 4)) for (ce in 0:1) for (ab in 0:1) add("moment", c(a, ord, ce, ab), moment(x, ord, ce == 1, ab == 1))
  add("skew", a, skewness(x)); add("kurt", a, kurtosis(x))
  jb <- jarque.test(x); add("jb_stat", a, unname(jb$statistic)); add("jb_p", a, jb$p.value)
  for (al in 0:2) {
    ag <- agostino.test(x, alt[al + 1]); an <- anscombe.test(x, alt[al + 1]); bo <- bonett.test(x, alt[al + 1])
    b <- c(a, al)
    add("agostino_skew", b, ag$statistic[1]); add("agostino_z", b, ag$statistic[2]); add("agostino_p", b, ag$p.value)
    add("anscombe_kurt", b, an$statistic[1]); add("anscombe_z", b, an$statistic[2]); add("anscombe_p", b, an$p.value)
    add("bonett_tau", b, bo$statistic[1]); add("bonett_z", b, bo$statistic[2]); add("bonett_p", b, bo$p.value)
  }
  l <- lillie.test(x); add("lillie_d", a, unname(l$statistic)); add("lillie_p", a, l$p.value)
  cv <- cvm.test(x); add("cvm_w", a, unname(cv$statistic)); add("cvm_p", a, cv$p.value)
  s <- sf.test(x); add("sf_w", a, unname(s$statistic)); add("sf_p", a, s$p.value)
  for (cl in c(0, 6)) for (adj in 0:1) {
    p <- if (cl == 0) pearson.test(x, adjust = adj == 1) else pearson.test(x, n.classes = cl, adjust = adj == 1)
    add("pearson_stat", c(a, cl, adj), unname(p$statistic)); add("pearson_p", c(a, cl, adj), p$p.value)
  }
}
emit("nortest", c("nortest", "moments"), list(cases))
