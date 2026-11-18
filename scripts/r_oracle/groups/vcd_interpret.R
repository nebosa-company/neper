# effectsize interpret_* label indices (1 = the first label) for rule ids: 0..3 cohens_d (cohen1988, sawilowsky2009, gignac2016, lovakov2021), 4..7 r (funder2019, gignac2016,
# cohen1988, lovakov2021), 8..9 eta_squared (field2013, cohen1992), 10 oddsratio. Args: (rule, x).
suppressMessages(library(effectsize))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
set.seed(20261250)
dr <- c("cohen1988", "sawilowsky2009", "gignac2016", "lovakov2021")
rr <- c("funder2019", "gignac2016", "cohen1988", "lovakov2021")
er <- c("field2013", "cohen1992")
lab_index <- function(lab) { l <- unclass(attr(lab, "rules"))$labels; match(as.character(lab), l) - 1 }
for (k in seq_along(dr)) {
  th <- unclass(attr(interpret_cohens_d(0.1, rules = dr[k]), "rules"))$values
  xs <- c(runif(40, -2.5, 2.5), th, -th, th - 1e-9, th + 1e-9)
  for (x in xs) add("i", c(k - 1, x), lab_index(interpret_cohens_d(x, rules = dr[k])))
}
for (k in seq_along(rr)) {
  th <- unclass(attr(interpret_r(0.1, rules = rr[k]), "rules"))$values
  xs <- c(runif(40, -1, 1), th, -th, th - 1e-9, th + 1e-9)
  for (x in xs) add("i", c(3 + k, x), lab_index(interpret_r(x, rules = rr[k])))
}
for (x in c(runif(30, -1, 1), c(0.05, 0.1, 0.2, 0.3, 0.4))) add("i", c(4, x), lab_index(interpret_rank_biserial(x)))
for (k in seq_along(er)) {
  th <- unclass(attr(interpret_eta_squared(0.1, rules = er[k]), "rules"))$values
  xs <- c(runif(40, 0, 0.5), th, th - 1e-9, th + 1e-9)
  for (x in xs) add("i", c(7 + k, x), lab_index(interpret_eta_squared(x, rules = er[k])))
}
for (x in c(exp(runif(60, -3, 3)), 1)) add("i", c(10, x), lab_index(interpret_oddsratio(x)))
emit("vcd_interpret", "effectsize", list(cases))
