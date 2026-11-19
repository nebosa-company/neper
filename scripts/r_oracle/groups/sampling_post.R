# sampling: postest(data with a poststratum column, y, pik, NG) without a Stratum column. Args: (n, G, y[n], pik[n], post[n], NG[G]), NG in order of first appearance of the post-strata.
suppressMessages(library(sampling))
cases <- list()
set.seed(20262329)
for (rep in 1:20) {
  n <- sample(12:40, 1); G <- sample(2:4, 1); post <- sample(1:G, n, replace = TRUE); post[1:G] <- sample(1:G)
  y <- round(rnorm(n, 20, 5), 3); pik <- round(runif(n, 0.1, 0.9), 3); NG <- sample(20:80, G, replace = TRUE)
  est <- postest(data.frame(poststratum = post), y, pik, NG)
  cases[[length(cases) + 1]] <- case("po", c(n, G, y, pik, post, NG), as.numeric(est), rel = 1e-10, abs = 1e-12)
}
# postest with a Stratum column: args (n, G, H, y[n], pik[n], post[n], stratum[n], NG[H * G] row-major) under kind "pw".
for (rep in 1:20) {
  n <- sample(20:50, 1); G <- sample(2:3, 1); H <- sample(2:3, 1)
  post <- sample(1:G, n, replace = TRUE); post[1:G] <- sample(1:G); stratum <- sample(1:H, n, replace = TRUE); stratum[1:H] <- sample(1:H)
  y <- round(rnorm(n, 20, 5), 3); pik <- round(runif(n, 0.1, 0.9), 3); NG <- matrix(sample(10:40, H * G, replace = TRUE), H, G)
  est <- tryCatch(postest(data.frame(Stratum = stratum, poststratum = post), y, pik, NG), error = function(e) NULL); if (is.null(est)) next
  cases[[length(cases) + 1]] <- case("pw", c(n, G, H, y, pik, post, stratum, as.vector(t(NG))), as.numeric(est), rel = 1e-10, abs = 1e-12)
}
emit("sampling_post", "sampling", list(cases))
