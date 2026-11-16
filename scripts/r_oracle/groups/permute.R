# permute: shuffle under set.seed for free and series within restrictions, with plots (free or series),
# blocks and the constant option, and numPerms.
#   shuffle: (seed, n, plot_type, plot_mirror, within_type, within_mirror, constant, has_plots, has_blocks, plots[n], blocks[n], pos)
#     types 0 free 1 series 2 none; plots and blocks are labels 1..9 (zeros when absent)
#   nperms:  (n, plot_type, plot_mirror, within_type, within_mirror, constant, plots[n])  -> numPerms (single block)
library(permute)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 0)
tn <- c("free", "series", "none")
set.seed(20261115)
mkctl <- function(n, plots, blocks, pt, pm, wt, wm, cst) {
  how(within = Within(type = tn[wt + 1], mirror = wm == 1, constant = cst == 1),
      plots = if (is.null(plots)) Plots() else Plots(strata = factor(plots), type = tn[pt + 1], mirror = pm == 1),
      blocks = if (is.null(blocks)) NULL else factor(blocks), nperm = 1)
}
designs <- list(
  list(n = 12, plots = NULL, blocks = NULL), list(n = 12, plots = rep(1:3, each = 4), blocks = NULL),
  list(n = 12, plots = rep(1:4, each = 3), blocks = NULL), list(n = 12, plots = rep(1:2, each = 6), blocks = NULL),
  list(n = 12, plots = rep(rep(1:3, each = 2), 2), blocks = rep(1:2, each = 6)), list(n = 10, plots = NULL, blocks = rep(1:2, each = 5)),
  list(n = 8, plots = rep(1:2, each = 4), blocks = NULL))
for (dsn in designs) {
  n <- dsn$n
  for (pt in 0:2) for (wt in 0:2) for (pm in 0:1) for (wm in 0:1) for (cst in 0:1) {
    if (is.null(dsn$plots) && (pt != 0 || pm == 1 || cst == 1)) next
    if (!is.null(dsn$plots) && is.null(dsn$blocks) && pt == 2 && wt == 2) next
    if (!is.null(dsn$blocks) && !is.null(dsn$plots) && pt != 0) next
    ctl <- tryCatch(suppressWarnings(mkctl(n, dsn$plots, dsn$blocks, pt, pm, wt, wm, cst)), error = function(e) NULL)
    if (is.null(ctl)) next
    seed <- sample(1e6, 1); set.seed(seed)
    r <- tryCatch(suppressWarnings(shuffle(n, ctl)), error = function(e) NULL)
    if (is.null(r)) next
    pl <- if (is.null(dsn$plots)) rep(0, n) else dsn$plots; bl <- if (is.null(dsn$blocks)) rep(0, n) else dsn$blocks
    a <- c(seed, n, pt, pm, wt, wm, cst, !is.null(dsn$plots), !is.null(dsn$blocks), pl, bl)
    for (i in seq_len(n)) add("shuffle", c(a, i - 1), r[i])
  }
}
for (dsn in designs) if (is.null(dsn$blocks)) {
  n <- dsn$n
  for (pt in 0:2) for (wt in 0:2) for (pm in 0:1) for (wm in 0:1) for (cst in 0:1) {
    if (is.null(dsn$plots) && (pt != 0 || pm == 1 || cst == 1)) next
    ctl <- tryCatch(suppressWarnings(mkctl(n, dsn$plots, NULL, pt, pm, wt, wm, cst)), error = function(e) NULL)
    if (is.null(ctl)) next
    v <- tryCatch(suppressWarnings(numPerms(n, ctl)), error = function(e) NULL)
    if (is.null(v) || !is.finite(v)) next
    pl <- if (is.null(dsn$plots)) rep(0, n) else dsn$plots
    add("nperms", c(n, pt, pm, wt, wm, cst, !is.null(dsn$plots), pl), v)
  }
}
emit("permute", "permute", list(cases))
