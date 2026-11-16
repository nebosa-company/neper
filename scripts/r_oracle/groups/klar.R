# klaR: NaiveBayes (Gaussian) fit and predict.
#   args: (n, p, k, m, x row-major n by p..., labels[n]..., test row-major m by p...)   fn "prior" (sum of prior * class), "mean" "sd" (sum of table value * position), "post" (sum of posterior * position), "cls" (sum of predicted class * position)
suppressMessages(library(klaR))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261228)
for (rep in 1:14) {
  n <- sample(30:90, 1); p <- sample(1:4, 1); k <- sample(2:4, 1); m <- 12
  g <- factor(sample(rep(1:k, length.out = n))); X <- matrix(rnorm(n * p), n, p) + matrix(as.numeric(g), n, p) * 0.7
  T <- matrix(rnorm(m * p) + sample(1:k, m * p, replace = TRUE) * 0.7, m, p)
  dfx <- as.data.frame(X); names(dfx) <- paste0("v", 1:p); dft <- as.data.frame(T); names(dft) <- names(dfx)
  nb <- NaiveBayes(dfx, g, usekernel = FALSE); pr <- predict(nb, dft)
  a <- c(n, p, k, m, as.vector(t(X)), as.numeric(g), as.vector(t(T)))
  add("prior", a, sum(nb$apriori * seq_len(k)))
  mm <- unlist(lapply(nb$tables, function(tb) as.vector(t(tb[, 1])))); 
  mean_t <- matrix(0, k, p); sd_t <- matrix(0, k, p); for (v in 1:p) { mean_t[, v] <- nb$tables[[v]][, 1]; sd_t[, v] <- nb$tables[[v]][, 2] }
  add("mean", a, sum(as.vector(t(mean_t)) * seq_len(k * p))); add("sd", a, sum(as.vector(t(sd_t)) * seq_len(k * p)))
  add("post", a, sum(as.vector(t(pr$posterior)) * seq_len(m * k))); add("cls", a, sum(as.numeric(pr$class) * seq_len(m)))
}
emit("klar", "klaR", list(cases))
