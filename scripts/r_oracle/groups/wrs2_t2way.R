# WRS2::t2way (trimmed means 0.2) on balanced-by-cell designs with J and K levels. Args: (J, K, sizes[J K], data[n], which) with the cells in R's
# order (cell (j, k) is group (j - 1) K + k, the second factor fastest); which 0 Qa, 1 A p value, 2 Qb, 3 B p value, 4 Qab, 5 AB p value.
suppressMessages(library(WRS2))
cases <- list()
add <- function(fn, args, want, rel = 1e-7, abs = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261236)
for (rep in 1:8) {
  J <- c(2, 3)[(rep - 1) %% 2 + 1]; K <- c(2, 3)[(rep - 1) %/% 2 %% 2 + 1]
  sizes <- sample(8:14, J * K, replace = TRUE)
  cells <- lapply(seq_len(J * K), function(g) round(rnorm(sizes[g]) * sd(1:3) + ((g - 1) %/% K) * 0.8 + ((g - 1) %% K) * 0.5, 3))
  d <- data.frame(y = unlist(cells), A = factor(rep(rep(seq_len(J), each = K), sizes)), B = factor(rep(rep(seq_len(K), J), sizes)))
  d$A <- factor(as.character(d$A)); d$B <- factor(as.character(d$B))
  w <- t2way(y ~ A + B, data = d, tr = 0.2)
  data <- as.numeric(unlist(cells))
  base <- c(J, K, sizes, data)
  add("t2", c(base, 0), w$Qa); add("t2", c(base, 1), w$A.p.value)
  add("t2", c(base, 2), w$Qb); add("t2", c(base, 3), w$B.p.value)
  add("t2", c(base, 4), w$Qab); add("t2", c(base, 5), w$AB.p.value)
}
emit("wrs2_t2way", "WRS2", list(cases))
