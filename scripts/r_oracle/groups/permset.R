# permute: shuffleSet(n, nset, control, check = FALSE) under set.seed.
#   args: (seed, n, nset, pt 0 free 1 series 2 none 3 grid, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, has_plots, has_blocks, plots[n], blocks[n], pos) pos indexes the nset x n matrix by rows
suppressMessages(library(permute))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("set", args, want, rel = 0, abs = 0)
tn <- c("free", "series", "none", "grid")
set.seed(20261118)
run <- function(plots, blocks, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst) {
  w <- if (wt == 3) Within(type = "grid", mirror = wm == 1, nrow = wr, ncol = wc, symmetric = ws == 1, constant = cst == 1) else Within(type = tn[wt + 1], mirror = wm == 1, constant = cst == 1)
  pl <- if (is.null(plots)) Plots() else if (pt == 3) Plots(strata = factor(plots), type = "grid", mirror = pm == 1, nrow = pr, ncol = pc, symmetric = ps == 1) else Plots(strata = factor(plots), type = tn[pt + 1], mirror = pm == 1)
  if (is.null(blocks)) how(within = w, plots = pl) else how(within = w, plots = pl, blocks = factor(blocks))
}
emitcase <- function(n, plots, blocks, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, nset = 5) {
  ctl <- tryCatch(suppressWarnings(run(plots, blocks, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst)), error = function(e) NULL)
  if (is.null(ctl)) return(invisible())
  seed <- sample(1e6, 1); set.seed(seed)
  r <- tryCatch(suppressWarnings(shuffleSet(n, nset, ctl, check = FALSE)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  v <- as.vector(t(unclass(r)[, , drop = FALSE]))
  a <- c(seed, n, nset, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, !is.null(plots), !is.null(blocks), if (is.null(plots)) rep(0, n) else plots, if (is.null(blocks)) rep(0, n) else blocks)
  for (i in seq_along(v)) add(c(a, i - 1), v[i])
}
for (n in c(6, 10)) for (wt in 0:3) for (wm in 0:1) emitcase(n, NULL, NULL, 0, 0, 0, 0, 0, if (wt == 3) 3 else wt, wm, 2, n / 2, 0, 0)
for (np in c(2, 3, 4)) for (per in c(3, 4)) for (pt in 0:2) for (wt in c(0, 1, 2)) for (cst in 0:1) for (pm in 0:1) for (wm in 0:1) {
  plots <- rep(seq_len(np), each = per)
  emitcase(np * per, plots, NULL, pt, pm, 0, 0, 0, wt, wm, 0, 0, 0, cst)
}
for (pg in list(c(2, 3), c(3, 3))) for (pm in 0:1) for (ps in 0:1) for (wt in c(0, 1)) for (cst in 0:1) {
  np <- pg[1] * pg[2]; plots <- rep(seq_len(np), each = 3)
  emitcase(np * 3, plots, NULL, 3, pm, pg[1], pg[2], ps, wt, 0, 0, 0, 0, cst)
}
for (dm in list(c(2, 3), c(3, 2))) for (wm in 0:1) for (ws in 0:1) for (cst in 0:1) {
  plots <- rep(1:3, each = 6)
  emitcase(18, plots, NULL, 0, 0, 0, 0, 0, 3, wm, dm[1], dm[2], ws, cst)
}
for (wt in 0:2) for (pt in 0:1) emitcase(12, rep(1:3, each = 4), rep(1:2, 6), pt, 0, 0, 0, 0, wt, 0, 0, 0, 0, 0)
for (wt in 0:2) for (cst in 0:1) emitcase(12, rep(rep(1:3, each = 2), 2), rep(1:2, each = 6), 2, 0, 0, 0, 0, wt, 0, 0, 0, 0, cst)
for (wt in 0:2) emitcase(12, NULL, rep(1:3, each = 4), 2, 0, 0, 0, 0, wt, 1, 0, 0, 0, 0)
emit("permset", "permute", list(cases))
