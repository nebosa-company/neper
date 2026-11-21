# igraph layout_with_drl (2-D, random start): the default schedule and shortened ones, weighted and unweighted.
# A layout is summarised as the sum and the row-weighted sum of each coordinate column.
#   fn "drl_<x|y><s|w>"; args: (seed, n, ne, hasw, opts [25] = edge.cut then (iterations, temperature, attraction, damping.mult) for init liquid expansion cooldown crunch simmer,
#   edges (0-based) [2*ne], weights [ne when hasw])
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want, tol) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = tol / 10)
dflt <- c(0.8, 0, 2000, 10, 1, 200, 2000, 10, 1, 200, 2000, 2, 1, 200, 2000, 1, 0.1, 50, 250, 1, 0.25, 100, 250, 0.5, 0)
nm <- c("edge.cut", unlist(lapply(c("init", "liquid", "expansion", "cooldown", "crunch", "simmer"), function(s) paste0(s, c(".iterations", ".temperature", ".attraction", ".damping.mult")))))
lay <- function(g, seed, w, opts, tol) {
  n <- vcount(g); e <- as_edgelist(g, names = FALSE) - 1; hasw <- !is.null(w)
  hdr <- c(seed, n, nrow(e), hasw, opts, as.vector(t(e)), if (hasw) w)
  set.seed(seed)
  m <- tryCatch(layout_with_drl(g, options = as.list(setNames(opts, nm)), weights = w), error = function(e) NULL)
  if (is.null(m)) return(invisible())
  for (k in 1:2) {
    col <- c("x", "y")[k]
    add(paste0("drl_", col, "s"), hdr, sum(m[, k]), tol); add(paste0("drl_", col, "w"), hdr, sum(seq_len(n) * m[, k]), tol)
  }
}
set.seed(20261125)
sd <- 11000
for (rep in 1:30) {
  n <- sample(5:35, 1); g <- sample_gnp(n, runif(1, 0.05, 0.4)); if (ecount(g) == 0) next
  w <- if (rep %% 4 == 0) round(runif(ecount(g), 0.5, 2), 3) else NULL
  o <- dflt
  if (rep %% 3 == 1) { o[7] <- 40; o[10] <- 30; o[13] <- 30; o[19] <- 20; o[22] <- 30 }
  if (rep %% 3 == 2) { o[1] <- c(0.5, 0.99)[rep %% 2 + 1]; o[7] <- 60; o[10] <- 40; o[13] <- 40; o[19] <- 20; o[22] <- 30 }
  sd <- sd + 1; lay(g, sd, w, o, 1e-9)
}
emit("igraph_drl", "igraph", list(cases))
