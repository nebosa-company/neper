# fpc::cdbw.
#   "cdbw": (what, r, ns, clusterstdev, n, p, cn, s[ns], labels[n], x n by p row-major); what 0 cdbw, 1 cohesion, 2 compactness, 3 sep
suppressMessages(library(fpc))
cases <- list()
set.seed(20269983)
flat <- function(m) as.vector(t(unclass(m)))
for (rep in 1:18) {
  p <- sample(2:4, 1); cn <- sample(2:4, 1); n <- sample(40:80, 1); r <- c(3, 5, 10)[rep %% 3 + 1]
  cl <- sample(rep(1:cn, length.out = n)); cl[1:cn] <- 1:cn
  x <- round(matrix(rnorm(n * p, sd = c(0.5, 1)[rep %% 2 + 1]), n, p) + outer(cl, seq_len(p)) * 1.5, 4)
  cs <- rep %% 4 < 2
  s <- if (rep %% 3 == 0) seq(0.1, 0.8, by = 0.1) else c(0.2, 0.5, 0.7, 0.9)[1:(2 + rep %% 3)]
  v <- cdbw(x, cl, r = r, s = s, clusterstdev = cs)
  for (w in 0:3) cases[[length(cases) + 1]] <- case("cdbw", c(w, r, length(s), as.numeric(cs), n, p, cn, s, cl, flat(x)), v[[c("cdbw", "cohesion", "compactness", "sep")[w + 1]]], rel = 1e-9, abs = 1e-12)
}
emit("fpc_cdbw", "fpc", list(cases))
