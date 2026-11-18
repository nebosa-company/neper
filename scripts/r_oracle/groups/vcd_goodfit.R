# vcd::goodfit(type = "poisson", method = "ML") on a one-way table of counts. Args: (K, freq[K], which): the counts are 0 .. K - 1;
# which 0 lambda, 1 the sum of the fitted counts, 2 the degrees of freedom, 3 the chi-square sum (obs - fit)^2 / fit (summary.goodfit).
suppressMessages(library(vcd))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261243)
for (rep in 1:16) {
  lam <- runif(1, 0.5, 6); n <- sample(40:300, 1)
  x <- rpois(n, lam)
  g <- goodfit(x, type = "poisson", method = "ML")
  freq <- as.numeric(g$observed); K <- length(freq); fit <- as.numeric(g$fitted)
  base <- c(K, freq)
  add("gf", c(base, 0), as.numeric(g$par$lambda))
  add("gf", c(base, 1), sum(fit))
  add("gf", c(base, 2), g$df)
  add("gf", c(base, 3), sum((freq - fit)^2 / fit))
}
# binomial: counts 0 .. size with size = 8 (the first K entries are the counts; 'size' is passed as the last-but-one argument, before which)
for (rep in 1:12) {
  size <- 8; pr <- runif(1, 0.2, 0.8); n <- sample(40:200, 1)
  x <- rbinom(n, size, pr)
  g <- goodfit(x, type = "binomial", method = "ML", par = list(size = size))
  freq <- as.numeric(g$observed); K <- length(freq); fit <- as.numeric(g$fitted)
  base <- c(K, freq)
  add("gb", c(size, base, 0), as.numeric(g$par$prob))
  add("gb", c(size, base, 1), sum(fit))
  add("gb", c(size, base, 2), g$df)
  add("gb", c(size, base, 3), sum((freq - fit)^2 / fit))
}
# MinChisq: "gm" (Poisson; K, freq, which) and "gbm" (binomial; size, K, freq, which), which 0 parameter, 1 sum of fitted, 2 df, 3 chi-square
for (rep in 1:12) {
  lam <- runif(1, 0.5, 6); n <- sample(40:300, 1); x <- rpois(n, lam)
  g <- goodfit(x, type = "poisson", method = "MinChisq"); freq <- as.numeric(g$observed); K <- length(freq); fit <- as.numeric(g$fitted); base <- c(K, freq)
  add("gm", c(base, 0), as.numeric(g$par$lambda), rel = 1e-7); add("gm", c(base, 1), sum(fit)); add("gm", c(base, 2), g$df); add("gm", c(base, 3), sum((freq - fit)^2 / fit), rel = 1e-6)
  size <- 8; pr <- runif(1, 0.2, 0.8); n <- sample(40:200, 1); x <- rbinom(n, size, pr)
  g <- goodfit(x, type = "binomial", method = "MinChisq", par = list(size = size)); freq <- as.numeric(g$observed); K <- length(freq); fit <- as.numeric(g$fitted); base <- c(K, freq)
  add("gbm", c(size, base, 0), as.numeric(g$par$prob), rel = 1e-7); add("gbm", c(size, base, 1), sum(fit)); add("gbm", c(size, base, 2), g$df); add("gbm", c(size, base, 3), sum((freq - fit)^2 / fit), rel = 1e-6)
}
# negative binomial: "gnb" args (method 0 ML / 1 MinChisq, K, freq, which) which 0 size, 1 prob; ML at 3e-3 (fitdistr BFGS stops short of the optimum), MinChisq under R's Nelder-Mead
for (rep in 1:14) {
  n <- sample(80:300, 1); x <- rnbinom(n, mu = runif(1, 1, 6), size = runif(1, 1, 5)); if (var(x) <= mean(x)) next
  gl <- tryCatch(suppressWarnings(goodfit(x, type = "nbinomial", method = "ML")), error = function(e) NULL)
  if (!is.null(gl)) { freq <- as.numeric(gl$observed); K <- length(freq); b <- c(0, K, freq)
    add("gnb", c(b, 0), as.numeric(gl$par$size), rel = 3e-3, abs = 1e-4); add("gnb", c(b, 1), as.numeric(gl$par$prob), rel = 3e-3, abs = 1e-4) }
  gm <- tryCatch(suppressWarnings(goodfit(x, type = "nbinomial", method = "MinChisq")), error = function(e) NULL)
  if (!is.null(gm)) { freq <- as.numeric(gm$observed); K <- length(freq); b <- c(1, K, freq)
    add("gnb", c(b, 0), as.numeric(gm$par$size), rel = 1e-6, abs = 1e-8); add("gnb", c(b, 1), as.numeric(gm$par$prob), rel = 1e-6, abs = 1e-8) }
}
emit("vcd_goodfit", "vcd", list(cases))
