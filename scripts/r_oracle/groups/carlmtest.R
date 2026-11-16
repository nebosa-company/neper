# car, lmtest, sandwich: vcovHC (HC0 to HC4), dwtest, studentized bptest and vif of a linear model.
#   args: (n, p, y[n]..., X row-major n by p with the intercept column...)   fn "hc0" .. "hc4" (sum of diag(vcovHC) * position), "dw", "bp", "vif" (sum of vif * position)
suppressMessages({library(car); library(lmtest); library(sandwich)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-12)
set.seed(20261228)
for (rep in 1:12) {
  n <- sample(20:70, 1); k <- sample(2:4, 1)
  X <- matrix(rnorm(n * k), n, k); for (j in 2:k) X[, j] <- X[, j] + 0.6 * X[, j - 1]
  y <- 1 + X %*% (1:k / 2) + rnorm(n) * (1 + abs(X[, 1])); colnames(X) <- paste0("v", 1:k)
  d <- data.frame(y = as.vector(y), X); m <- lm(y ~ ., d)
  des <- cbind(1, X); a <- c(n, k + 1, as.vector(y), as.vector(t(des)))
  for (t in 0:4) { dv <- diag(vcovHC(m, paste0("HC", t))); add(paste0("hc", t), a, sum(dv * seq_along(dv))) }
  add("dw", a, as.numeric(dwtest(m)$statistic)); add("bp", a, as.numeric(bptest(m)$statistic))
  add("bpc", a, as.numeric(bptest(m, studentize = FALSE)$statistic)); add("reset", a, as.numeric(resettest(m)$statistic)); add("bpp", a, bptest(m)$p.value); g <- gqtest(m); add("gq", a, as.numeric(g$statistic)); add("gqp", a, g$p.value); add("resetp", a, resettest(m)$p.value)
  for (lg in c(2, 4)) for (ad in c(FALSE, TRUE)) { dv <- diag(NeweyWest(m, lag = lg, prewhite = FALSE, adjust = ad)); add("nw", c(a, lg, as.numeric(ad)), sum(dv * seq_along(dv))) }
  rt <- raintest(m); add("rain", a, as.numeric(rt$statistic)); add("rainp", a, rt$p.value); ht <- harvtest(m); add("harv", a, as.numeric(ht$statistic)); add("harvp", a, ht$p.value)
  for (ord in c(1, 2, 4)) { a2 <- c(a, ord); b1 <- bgtest(m, order = ord); b2 <- bgtest(m, order = ord, type = "F"); add("bg_c", a2, as.numeric(b1$statistic)); add("bg_cp", a2, b1$p.value); add("bg_f", a2, as.numeric(b2$statistic)); add("bg_fp", a2, b2$p.value) }
  if (k >= 2) { v <- vif(m); add("vif", a, sum(v * seq_along(v))) }
}
for (rep in 1:10) {
  n <- sample(30:80, 1); ng <- sample(4:10, 1); g <- sample(seq_len(ng), n, replace = TRUE); ng <- length(unique(g)); gi <- match(g, sort(unique(g))) - 1
  k <- sample(1:3, 1); X <- matrix(rnorm(n * k), n, k); y <- 1 + X %*% rep(0.5, k) + rnorm(n) + gi / 4
  d <- data.frame(y = as.vector(y), X); m <- lm(y ~ ., d); des <- cbind(1, X); a <- c(n, k + 1, as.vector(y), as.vector(t(des)))
  for (ty in c("HC0", "HC1")) for (ca in c(FALSE, TRUE)) { dv <- diag(vcovCL(m, cluster = g, type = ty, cadjust = ca)); add("cl", c(a, ng, as.numeric(ty == "HC1"), as.numeric(ca), gi), sum(dv * seq_along(dv))) }
}
emit("carlmtest", "car", list(cases))
