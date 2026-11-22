# klaR::woe for one factor variable against a binary target.
#   args: (n, nlev, zeroadj, codes[n] (0-based levels), labels[n] (1 or 2))
#   fn "woe": the per-level weights of evidence followed by the information value, each weighted by its
#   1-based position and accumulated in a double loop
suppressMessages(library(klaR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("woe", args, want, rel = 1e-9, abs = 1e-12)
wsum <- function(v) { s <- 0; for (i in seq_along(v)) s <- s + v[i] * i; s }
set.seed(20261230)
for (rep in 1:20) {
  n <- sample(30:80, 1); L <- sample(2:4, 1); L2 <- sample(2:3, 1)
  adj <- c(0, 0.5, 1)[(rep %% 3) + 1]
  y <- factor(sample(c(1, 2), n, replace = TRUE))
  x1 <- (sample(0:(L - 1), n, replace = TRUE) + as.integer(y) - 1) %% L
  # a level absent from one class on some draws, so zeroadj is exercised
  if (rep %% 2 == 0) x1[y == "2" & x1 == 0] <- 1
  x2 <- sample(0:(L2 - 1), n, replace = TRUE)
  d <- data.frame(x1 = factor(x1, levels = 0:(L - 1)), x2 = factor(x2, levels = 0:(L2 - 1)))
  w <- woe(d, y, zeroadj = adj)
  for (v in c("x1", "x2")) {
    co <- w$woe[[v]]
    vals <- c(as.numeric(co), as.numeric(w$IV[v]))
    if (!all(is.finite(vals))) next
    codes <- as.numeric(d[[v]]) - 1
    nlev <- nlevels(d[[v]])
    add(c(n, nlev, adj, codes, as.numeric(y)), wsum(vals))
  }
}
emit("klar_woe", "klaR", list(cases))
