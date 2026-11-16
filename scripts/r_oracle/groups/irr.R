# irr: agree, kappa2, kappam.fleiss, kappam.light, kendall, meancor, maxwell, robinson, finn, icc and kripp.alpha.
#   ratings are ns by nr row-major; j picks a field (value, statistic, p.value, ...)
#   agree (ns, nr, tol, X); kappa2 (ns, weight 0 unweighted 1 equal 2 squared 3 numeric, nw, w[nw], X (ns by 2), j 0 value 1 z 2 p); fleiss (ns, nr, exact, X, j);
#   light (ns, nr, X, j); kendall (ns, nr, correct, X, j); meancor (ns, nr, fisher, X, j); maxwell (ns, X); robinson (ns, nr, X); finn (ns, nr, s.levels, twoway, X, j);
#   icc (ns, nr, model 0 oneway 1 twoway, type 0 consistency 1 agreement, unit 0 single 1 average, r0, conf, X, j 0..6 value F df1 df2 p lbound ubound);
#   kripp (nrat, nobj, method 0 nominal 1 ordinal 2 interval 3 ratio, X nrat by nobj row-major, -999 missing)
suppressMessages(library(irr))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
set.seed(20261121)
flat <- function(m) as.vector(t(m))
cat_ratings <- function(ns, nr, K) { base <- sample(1:K, ns, TRUE); m <- sapply(1:nr, function(j) ifelse(runif(ns) < 0.65, base, sample(1:K, ns, TRUE))); matrix(m, ns, nr) }
for (rep in 1:10) {
  ns <- c(20, 30, 45, 12, 60)[(rep - 1) %% 5 + 1]; nr <- c(2, 3, 4, 5)[(rep - 1) %% 4 + 1]; K <- c(3, 4, 5)[(rep - 1) %% 3 + 1]
  X <- cat_ratings(ns, nr, K); Xn <- round(matrix(rnorm(ns * nr, 10, 2), ns, nr) + rnorm(ns) * 3, 1)
  add("agree", c(ns, nr, 0, flat(X)), agree(X)$value); add("agree", c(ns, nr, 1, flat(X)), agree(X, 1)$value); add("agree", c(ns, nr, 2, flat(Xn)), agree(Xn, 2)$value)
  f <- kappam.fleiss(X); add("fleiss", c(ns, nr, 0, flat(X), 0), f$value); add("fleiss", c(ns, nr, 0, flat(X), 1), f$statistic); add("fleiss", c(ns, nr, 0, flat(X), 2), f$p.value)
  add("fleiss", c(ns, nr, 1, flat(X), 0), kappam.fleiss(X, exact = TRUE)$value)
  if (nr >= 3) { l <- kappam.light(X); add("light", c(ns, nr, flat(X), 0), l$value); add("light", c(ns, nr, flat(X), 1), l$statistic); add("light", c(ns, nr, flat(X), 2), l$p.value) }
  for (co in 0:1) { k <- kendall(Xn, correct = co == 1); add("kendall", c(ns, nr, co, flat(Xn), 0), k$value); add("kendall", c(ns, nr, co, flat(Xn), 1), k$statistic); add("kendall", c(ns, nr, co, flat(Xn), 2), k$p.value) }
  Xr <- matrix(sample(1:5, ns * nr, TRUE), ns, nr)
  k <- kendall(Xr, correct = TRUE); add("kendall", c(ns, nr, 1, flat(Xr), 0), k$value); add("kendall", c(ns, nr, 1, flat(Xr), 2), k$p.value)
  if (nr >= 2) for (fi in 0:1) { m <- meancor(Xn, fisher = fi == 1); add("meancor", c(ns, nr, fi, flat(Xn), 0), m$value); if (fi == 1) { add("meancor", c(ns, nr, fi, flat(Xn), 1), m$statistic); add("meancor", c(ns, nr, fi, flat(Xn), 2), m$p.value) } }
  add("robinson", c(ns, nr, flat(Xn)), robinson(Xn)$value)
  for (tw in 0:1) { f2 <- finn(Xr, 5, model = c("oneway", "twoway")[tw + 1]); add("finn", c(ns, nr, 5, tw, flat(Xr), 0), f2$value); add("finn", c(ns, nr, 5, tw, flat(Xr), 1), f2$statistic); add("finn", c(ns, nr, 5, tw, flat(Xr), 2), f2$p.value) }
  for (mo in 0:1) for (ty in 0:1) for (un in 0:1) {
    if (mo == 0 && ty == 1) next
    r <- icc(Xn, model = c("oneway", "twoway")[mo + 1], type = c("consistency", "agreement")[ty + 1], unit = c("single", "average")[un + 1], r0 = 0.2, conf.level = 0.9)
    a <- c(ns, nr, mo, ty, un, 0.2, 0.9, flat(Xn))
    vals <- c(r$value, r$Fvalue, r$df1, r$df2, r$p.value, r$lbound, r$ubound)
    for (j in 0:6) add("icc", c(a, j), vals[j + 1], rel = 1e-8)
  }
  for (me in 0:3) { Y <- t(X); r <- kripp.alpha(Y, c("nominal", "ordinal", "interval", "ratio")[me + 1]); add("kripp", c(nr, ns, me, flat(Y)), r$value) }
  Y <- t(X); Y[sample(length(Y), length(Y) %/% 8)] <- NA; Y[, colSums(!is.na(Y)) < 2] <- 1
  for (me in 0:3) { r <- tryCatch(kripp.alpha(Y, c("nominal", "ordinal", "interval", "ratio")[me + 1]), error = function(e) NULL); if (!is.null(r)) add("kripp", c(nr, ns, me, flat(ifelse(is.na(Y), -999, Y))), r$value) }
}
for (rep in 1:6) {
  ns <- c(25, 40, 60)[(rep - 1) %% 3 + 1]; K <- c(3, 4, 5)[(rep - 1) %% 3 + 1]
  X <- cat_ratings(ns, 2, K)
  for (wt in 0:2) { k <- kappa2(X, c("unweighted", "equal", "squared")[wt + 1]); for (j in 0:2) add("kappa2", c(ns, wt, 0, flat(X), j), c(k$value, k$statistic, k$p.value)[j + 1]) }
  X2 <- cat_ratings(ns, 2, 2); add("maxwell", c(ns, flat(X2)), maxwell(X2)$value)
}
#   iota (ns, nr, nvar, nominal, standardize, X: nvar matrices of ns by nr row-major one after another)
for (rep in 1:6) {
  ns <- c(20, 30, 45)[(rep - 1) %% 3 + 1]; nr <- c(3, 4)[(rep - 1) %% 2 + 1]; nvar <- c(1, 2, 3)[(rep - 1) %% 3 + 1]
  L <- lapply(1:nvar, function(i) round(matrix(rnorm(ns * nr, i, 2), ns, nr) + rnorm(ns), 1))
  for (st in 0:1) add("iota", c(ns, nr, nvar, 0, st, unlist(lapply(L, flat))), iota(L, "quantitative", standardize = st == 1)$value)
  Lc <- lapply(1:nvar, function(i) cat_ratings(ns, nr, 4))
  add("iota", c(ns, nr, nvar, 1, 0, unlist(lapply(Lc, flat))), iota(Lc, "nominal")$value)
}
emit("irr", "irr", list(cases))
