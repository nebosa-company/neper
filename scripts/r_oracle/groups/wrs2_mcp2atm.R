# WRS2::mcp2atm (trimmed means 0.2): the contrasts' psihat, standard error-based test and p value for the A, B and AB effects. Args: (J, K, which, c, what, sizes[J K], data[n]):
# cells in R's order (cell (j, k) is group (j - 1) K + k); which 0 A, 1 B, 2 AB; c the 0-based contrast; what 0 psihat, 1 p value, 2 lower limit, 3 upper limit.
suppressMessages(library(WRS2))
cases <- list()
set.seed(20261802)
add <- function(args, want, rel = 1e-7, abs = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("m", args, want, rel = rel, abs = abs)
for (rep in 1:4) {
  J <- c(2, 3, 3, 2)[rep]; K <- c(3, 2, 3, 2)[rep]
  sizes <- sample(10:16, J * K, replace = TRUE)
  cells <- lapply(seq_len(J * K), function(g) round(rnorm(sizes[g]) * 1.2 + ((g - 1) %/% K) * 0.8 + ((g - 1) %% K) * 0.5, 3))
  d <- data.frame(y = unlist(cells), A = factor(rep(rep(seq_len(J), each = K), sizes)), B = factor(rep(rep(seq_len(K), J), sizes)))
  d$A <- factor(as.character(d$A)); d$B <- factor(as.character(d$B))
  r <- mcp2atm(y ~ A * B, data = d, tr = 0.2)
  flat <- unlist(cells)
  for (w in 0:2) {
    e <- r$effects[[w + 1]]
    for (c in seq_along(e$psihat)) {
      add(c(J, K, w, c - 1, 0, sizes, flat), unname(e$psihat[c]))
      add(c(J, K, w, c - 1, 1, sizes, flat), unname(e$p.value[c]))
      add(c(J, K, w, c - 1, 2, sizes, flat), unname(matrix(e$conf.int, ncol = 2)[c, 1]))
      add(c(J, K, w, c - 1, 3, sizes, flat), unname(matrix(e$conf.int, ncol = 2)[c, 2]))
    }
  }
}
emit("wrs2_mcp2atm", "WRS2", list(cases))
