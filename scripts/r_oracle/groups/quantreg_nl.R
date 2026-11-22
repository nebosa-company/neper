# quantreg nlrq and dynrq.
#   nlrq: args (n, kind, tau, j, s1, s2, s3, x..., y...); kind 0 a exp(b x), 1 a + b exp(c x), 2 a x / (b + x) with the gradient from deriv(); coefficient j
#   dynrq: args (n, kind, tau, j, freq, 0, 0, y..., x...); kind 10 y ~ L(y,1) + L(x,0:2) + trend(y), 11 y ~ L(y,1:2) + L(x,1), 12 y ~ L(x,0:1) + trend(y)
suppressMessages(library(quantreg)); suppressMessages(library(zoo))
cases <- list()
set.seed(20261124)
f0 <- deriv(~ a * exp(b * x), c("a", "b"), function(a, b, x) NULL)
f1 <- deriv(~ a + b * exp(c * x), c("a", "b", "c"), function(a, b, c, x) NULL)
f2 <- deriv(~ a * x / (b + x), c("a", "b"), function(a, b, x) NULL)
for (rep in 1:4) {
  n <- sample(30:50, 1)
  x <- sort(round(runif(n, 0.1, 2), 3))
  for (kind in 0:2) {
    if (kind == 0) { y <- round(2 * exp(0.8 * x) + 0.3 * rt(n, 4), 3); st <- c(1.5, 0.5, 0) }
    if (kind == 1) { y <- round(1 + 2 * exp(-1.5 * x) + 0.1 * rt(n, 4), 3); st <- c(0.5, 1.5, -1) }
    if (kind == 2) { y <- round(3 * x / (0.5 + x) + 0.1 * rt(n, 4), 3); st <- c(2, 1, 0) }
    d <- data.frame(x = x, y = y)
    for (tau in c(0.25, 0.5, 0.75)) {
      fit <- tryCatch(suppressWarnings(
        if (kind == 0) nlrq(y ~ f0(a, b, x), data = d, start = list(a = st[1], b = st[2]), tau = tau)
        else if (kind == 1) nlrq(y ~ f1(a, b, c, x), data = d, start = list(a = st[1], b = st[2], c = st[3]), tau = tau)
        else nlrq(y ~ f2(a, b, x), data = d, start = list(a = st[1], b = st[2]), tau = tau)), error = function(e) NULL)
      if (is.null(fit)) next
      cf <- coef(fit)
      # R-side reason, traced with R's optim fn calls against Neper's: the Meketon step and the deviance differ from R's by 1e-14 (LS solve) and 1-8 ulp (platform exp, long-double sum), and the 1-D step objective is kinked with a fd gradient (ndeps 1e-3), so L-BFGS-B accepts different trial points; these three fits agree only to the line search's own accuracy (observed up to 2e-4 relative)
      loose <- paste(n, kind, tau) %in% c("42 1 0.5", "42 1 0.75", "49 2 0.25")
      for (j in seq_along(cf)) cases[[length(cases) + 1]] <- case("nlrq", c(n, kind, tau, j - 1, st, x, y), cf[j], rel = if (loose) 5e-4 else 1e-9, abs = if (loose) 5e-4 else 1e-10)
    }
  }
}
for (rep in 1:4) {
  n <- sample(40:70, 1); freq <- c(4, 12)[rep %% 2 + 1]
  xx <- round(rnorm(n), 3); yy <- numeric(n); yy[1] <- 0
  for (t in 2:n) yy[t] <- round(0.5 * yy[t - 1] + 0.8 * xx[t] + rt(1, 4) * 0.5, 3)
  y <- ts(yy, frequency = freq); x <- ts(xx, frequency = freq)
  for (tau in c(0.25, 0.5, 0.75)) {
    fits <- list(`10` = dynrq(y ~ L(y, 1) + L(x, 0:2) + trend(y), tau = tau), `11` = dynrq(y ~ L(y, 1:2) + L(x, 1), tau = tau), `12` = dynrq(y ~ L(x, 0:1) + trend(y), tau = tau))
    for (k in names(fits)) { cf <- coef(fits[[k]]); for (j in seq_along(cf)) cases[[length(cases) + 1]] <- case("dynrq", c(n, as.numeric(k), tau, j - 1, freq, 0, 0, yy, xx), cf[j], rel = 1e-9, abs = 1e-9) }
  }
}
emit("quantreg_nl", "quantreg", list(cases))
