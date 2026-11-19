# fpc::cluster.varstats beyond the categorised count table: the varwise tables of an uncategorised variable and of a categorised one with proportions = TRUE or FALSE,
# the table(clusteri, x) of the clusterwise output and its mean, sd and quartiles. Plots and printed text are not compared.
#   "vt": (n, ncl, cats, prop, i, what, clustering[n], x[n]); what 0 the varwise table (cats = 0 uncategorised): sum((position) * value) over the (ncl + 1) by columns table row-major;
#         1 table(clusteri, x) of cluster i (rows FALSE, TRUE), position-weighted; 2..9 mean, sd, quartile 0..4 of cluster i; 10..17 the same for all observations
suppressMessages(library(fpc))
cases <- list()
set.seed(20269991)
add <- function(args, v) if (is.finite(v)) cases[[length(cases) + 1]] <<- case("vt", args, v, rel = 1e-9, abs = 1e-10)
for (rep in 1:20) {
  n <- sample(30:120, 1); ncl <- sample(2:4, 1); cl <- sample(seq_len(ncl), n, TRUE); cl[seq_len(ncl)] <- seq_len(ncl)
  x <- if (rep %% 2 == 0) round(rnorm(n, cl, 2), 1) else sample(1:8, n, TRUE) + cl
  cats <- c(0, 4, 6)[rep %% 3 + 1]; prop <- rep %% 4 < 2; i <- sample(ncl, 1)
  vd <- data.frame(x = x)
  vt <- suppressWarnings(cluster.varstats(cl, vd, clusterwise = FALSE, catvar = if (cats > 0) 1 else NULL, catvarcats = max(cats, 2), proportions = prop))[[1]]
  vtm <- unclass(vt); dimnames(vtm) <- NULL
  add(c(n, ncl, cats, as.numeric(prop), i, 0, cl, x), sum(seq_along(t(vtm)) * as.vector(t(vtm))))
  ci <- cl == i
  tt <- table(ci, x); if (prop) tt <- prop.table(tt, 1)
  ttm <- unclass(tt); dimnames(ttm) <- NULL
  add(c(n, ncl, cats, as.numeric(prop), i, 1, cl, x), sum(seq_along(t(ttm)) * as.vector(t(ttm))))
  for (grp in 0:1) {
    v <- if (grp == 0) x[ci] else x
    qq <- quantile(v, probs = seq(0, 1, 0.25))
    vals <- c(mean(v), sd(v), as.numeric(qq))
    for (k in 1:7) add(c(n, ncl, cats, as.numeric(prop), i, 1 + k + 8 * grp, cl, x), vals[k])
  }
}
emit("fpc_varstats", "fpc", list(cases))
