# the fits behind mice's polyreg, polr and cart: rpart trees (anova and class), nnet::multinom and MASS::polr, each as a checksum of the predictions on new rows.
# args: (n, p, nt, k, minbucket, cp, x[n*p] column-major, y[n], xt[nt*p]); the answer is sum_i (i+1) pred_i (anova) or sum over rows and classes of (i*k+c+1) prob (class, multinom, polr)
suppressMessages({ library(rpart); library(nnet); library(MASS) })
cases <- list()
set.seed(20261117)
mkx <- function(n, p) {
  X <- matrix(round(rnorm(n * p), 2), n, p)
  if (p >= 2 && runif(1) < 0.7) X[, p] <- as.numeric(X[, p] > 0)
  X
}
chk <- function(v) sum(seq_along(v) * v)
# rpart anova
for (rep in 1:60) {
  n <- sample(20:70, 1); p <- sample(1:4, 1); nt <- 6; mb <- sample(c(3, 5), 1)
  X <- mkx(n, p); y <- round(X[, 1] * 2 + (if (p > 1) X[, 2] else 0) + rnorm(n, 0, 0.8), 3)
  if (rep %% 3 == 0) y <- round(y * 2) / 2
  xt <- mkx(nt, p); colnames(X) <- colnames(xt) <- paste0("V", 1:p)
  df <- data.frame(X); yobs <- y
  fit <- rpart(yobs ~ ., data = cbind(yobs, df), method = "anova", control = rpart.control(minbucket = mb, cp = 1e-4))
  pr <- as.numeric(predict(fit, newdata = data.frame(xt)))
  cases[[length(cases) + 1]] <- case("rpart_anova", c(n, p, nt, 0, mb, 1e-4, X, y, xt), chk(pr), rel = 1e-9, abs = 1e-9)
}
# rpart class
for (rep in 1:60) {
  n <- sample(25:80, 1); p <- sample(1:4, 1); nt <- 6; k <- sample(2:4, 1); mb <- sample(c(3, 5), 1)
  X <- mkx(n, p); sc <- X[, 1] + (if (p > 1) X[, 2] else 0) + rnorm(n, 0, 0.7)
  y <- as.integer(cut(sc, breaks = quantile(sc, seq(0, 1, length.out = k + 1)), include.lowest = TRUE))
  if (length(unique(y)) < 2) next
  xt <- mkx(nt, p); colnames(X) <- colnames(xt) <- paste0("V", 1:p)
  yobs <- factor(y); xy <- cbind(yobs, data.frame(X)); xy <- droplevels(xy)
  fit <- rpart(yobs ~ ., data = xy, method = "class", control = rpart.control(minbucket = mb, cp = 1e-4))
  pr <- predict(fit, newdata = data.frame(xt))
  kk <- length(levels(yobs))
  cases[[length(cases) + 1]] <- case("rpart_class", c(n, p, nt, kk, mb, 1e-4, X, as.integer(yobs), xt), chk(as.vector(t(pr))), rel = 1e-9, abs = 1e-9)
}
emit("micefit", c("rpart", "nnet", "MASS"), list(cases))
