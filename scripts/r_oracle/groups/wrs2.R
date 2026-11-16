# WRS2 (deterministic part): winvar winmean winse trimse tmean pbos, yuen, yuend, t1way, wincor, pbcor, akp.effect, lincon, med1way.
#   one-sample: fn "winvar" "winmean" "winse" "trimse" "tmean" "pbos" "msmedse": (tr, n, x)
#   yuen: (tr, n1, x, n2, y, j) j 0 test 1 ci.lower 2 ci.upper 3 p.value 4 df 5 diff 6 effsize (equal trimmed sizes only);  yuend: (tr, n, x, y, j) the same plus 7 se
#   t1way: (tr, k, sizes[k], data, j) j 0 test 1 df1 2 df2 3 p.value 4 effsize (equal sizes only);  med1way: (k, sizes[k], data) fn "med1way"
#   wincor: (tr, n, x, y, j) 0 cor 1 cov 2 test 3 p.value;  pbcor: (beta, n, x, y, j) 0 cor 1 test 2 p.value;  akp: (tr, eqvar, n1, x, n2, y)
#   lincon: (tr, k, sizes[k], data, pair, j) pair in R's order, j 0 psihat 1 test 2 se 3 df 4 p.value 5 Hochberg-adjusted p
suppressMessages(library(WRS2))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261123)
gen <- function(n, shift = 0) round(rlnorm(n, 0, 0.7) + shift + rnorm(n, 0, 0.3), 2)
for (rep in 1:8) {
  n <- c(20, 25, 30, 17, 40, 22)[(rep - 1) %% 6 + 1]
  for (tr in c(0.1, 0.2, 0.25)) {
    x <- gen(n); y <- gen(n, 0.4)
    add("winvar", c(tr, n, x), winvar(x, tr)); add("winmean", c(tr, n, x), winmean(x, tr)); add("winse", c(tr, n, x), winse(x, tr))
    add("trimse", c(tr, n, x), trimse(x, tr)); add("tmean", c(tr, n, x), mean(x, tr)); add("pbos", c(tr, n, x), WRS2:::pbos(x, tr)); add("msmedse", c(tr, n, x), WRS2:::msmedse(x))
    df <- data.frame(y = c(x, y), g = factor(rep(1:2, c(n, n))))
    r <- yuen(y ~ g, data = df, tr = tr)
    vals <- c(r$test, r$conf.int, r$p.value, r$df, r$diff, r$effsize)
    for (j in 0:6) add("yuen", c(tr, n, x, n, y, j), vals[j + 1])
    r <- yuend(x, y, tr = tr)
    vals <- c(r$test, r$conf.int, r$p.value, r$df, r$diff, r$effsize, r$se)
    for (j in 0:7) add("yuend", c(tr, n, x, y, j), vals[j + 1])
    w <- WRS2::wincor(x, y, tr = tr); vals <- c(w$cor, w$cov, w$test, w$p.value); for (j in 0:3) add("wincor", c(tr, n, x, y, j), vals[j + 1])
    p <- WRS2::pbcor(x, y, beta = tr); vals <- c(p$cor, p$test, p$p.value); for (j in 0:2) add("pbcor", c(tr, n, x, y, j), vals[j + 1])
    n2 <- n + 7; y2 <- gen(n2, 0.4)
    df2 <- data.frame(y = c(x, y2), g = factor(rep(1:2, c(n, n2))))
    r <- yuen(y ~ g, data = df2, tr = tr); vals <- c(r$test, r$conf.int, r$p.value, r$df, r$diff)
    for (j in 0:5) add("yuen", c(tr, n, x, n2, y2, j), vals[j + 1])
    for (eq in 0:1) { a <- suppressWarnings(akp.effect(y ~ g, data = df2, EQVAR = eq == 1, tr = tr, nboot = 2)); add("akp", c(tr, eq, n, x, n2, y2), a$AKPeffect) }
    for (k in 3:4) {
      sizes <- if (rep %% 2 == 0) rep(n, k) else n + 3 * (0:(k - 1)); dat <- unlist(lapply(seq_len(k), function(i) gen(sizes[i], 0.3 * i)))
      dfk <- data.frame(y = dat, g = factor(rep(1:k, sizes)))
      t1 <- suppressWarnings(t1way(y ~ g, data = dfk, tr = tr, nboot = 2)); vals <- c(t1$test, t1$df1, t1$df2, t1$p.value, if (length(unique(sizes)) == 1) t1$effsize else NA)
      for (j in 0:4) add("t1way", c(tr, k, sizes, dat, j), vals[j + 1])
      lc <- suppressWarnings(lincon(y ~ g, data = dfk, tr = tr)); cm <- lc$comp
      for (pr in seq_len(nrow(cm))) { add("lincon", c(tr, k, sizes, dat, pr - 1, 0), cm[pr, "psihat"]); add("lincon", c(tr, k, sizes, dat, pr - 1, 5), cm[pr, "p.value"]) }
    }
  }
  k <- 3; sizes <- c(n, n + 2, n + 5); dat <- unlist(lapply(1:k, function(i) gen(sizes[i], 0.3 * i)))
  m1 <- tryCatch(suppressWarnings(med1way(y ~ g, data = data.frame(y = dat, g = factor(rep(1:k, sizes))), iter = 10)), error = function(e) NULL)
  if (!is.null(m1)) add("med1way", c(k, sizes, dat), m1$test)
}
emit("wrs2", "WRS2", list(cases))
