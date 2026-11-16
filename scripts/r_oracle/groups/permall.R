# permute: allPerms of a design with within, plot-level and block restrictions.
#   args: (n, pt 0 free 1 series 2 none 3 grid, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, has_plots, has_blocks, plots[n], blocks[n], q)
#   fn "all": q 0 rows 1 sum 2 position-weighted sum (row-major) 3 sum of the last row 4 weighted sum of the first row
suppressMessages(library(permute))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("all", args, want, rel = 0, abs = 0)
tn <- c("free", "series", "none", "grid")
set.seed(20261118)
run <- function(plots, blocks, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst) {
  w <- if (wt == 3) Within(type = "grid", mirror = wm == 1, nrow = wr, ncol = wc, symmetric = ws == 1, constant = cst == 1) else Within(type = tn[wt + 1], mirror = (wm == 1 && wt == 1), constant = cst == 1)
  pl <- if (is.null(plots)) Plots() else if (pt == 3) Plots(strata = factor(plots), type = "grid", mirror = pm == 1, nrow = pr, ncol = pc, symmetric = ps == 1) else Plots(strata = factor(plots), type = tn[pt + 1], mirror = (pm == 1 && pt == 1))
  if (is.null(blocks)) how(within = w, plots = pl) else how(within = w, plots = pl, blocks = factor(blocks))
}
emitcase <- function(n, plots, blocks, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst) {
  ctl <- tryCatch(suppressWarnings(run(plots, blocks, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst)), error = function(e) NULL)
  if (is.null(ctl)) return(invisible())
  r <- tryCatch(suppressWarnings(allPerms(n, ctl, check = FALSE)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  m <- unclass(r); attributes(m) <- list(dim = dim(r)); v <- as.vector(t(m))
  a <- c(n, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, !is.null(plots), !is.null(blocks), if (is.null(plots)) rep(0, n) else plots, if (is.null(blocks)) rep(0, n) else blocks)
  add(c(a, 0), nrow(m)); add(c(a, 1), sum(v)); add(c(a, 2), sum(seq_along(v) * v)); add(c(a, 3), sum(m[nrow(m), ])); add(c(a, 4), sum(seq_len(ncol(m)) * m[1, ]))
}
for (n in c(3, 4, 5)) for (wt in 0:1) for (wm in 0:1) emitcase(n, NULL, NULL, 0, 0, 0, 0, 0, wt, wm, 0, 0, 0, 0)
for (dm in list(c(2, 2), c(3, 3), c(3, 4), c(2, 3), c(4, 3))) for (wm in 0:1) for (ws in 0:1) emitcase(dm[1] * dm[2], NULL, NULL, 0, 0, 0, 0, 0, 3, wm, dm[1], dm[2], ws, 0)
for (np in c(2, 3)) for (per in c(2, 3)) for (pt in 0:2) for (wt in 0:2) for (cst in 0:1) for (pm in 0:1) for (wm in 0:1) {
  if (pt == 2 && wt == 2) next
  emitcase(np * per, rep(seq_len(np), each = per), NULL, pt, pm, 0, 0, 0, wt, wm, 0, 0, 0, cst)
}
for (pg in list(c(2, 3), c(3, 2), c(2, 2))) for (pm in 0:1) for (ps in 0:1) for (wt in 0:2) for (cst in 0:1) {
  np <- pg[1] * pg[2]; if (np * 2 > 12 && wt == 0) next
  emitcase(np * 2, rep(seq_len(np), each = 2), NULL, 3, pm, pg[1], pg[2], ps, wt, 0, 0, 0, 0, cst)
}
for (dm in list(c(2, 3), c(3, 2))) for (wm in 0:1) for (cst in 0:1) emitcase(12, rep(1:2, each = 6), NULL, 0, 0, 0, 0, 0, 3, wm, dm[1], dm[2], 0, cst)
for (wt in 0:1) for (wm in 0:1) { emitcase(6, NULL, rep(1:2, each = 3), 2, 0, 0, 0, 0, wt, wm, 0, 0, 0, 0); emitcase(8, NULL, rep(1:2, 4), 2, 0, 0, 0, 0, wt, wm, 0, 0, 0, 0) }
for (wt in 0:1) for (pt in 0:1) emitcase(8, rep(1:2, each = 2), rep(1:2, each = 4), pt, 0, 0, 0, 0, wt, 0, 0, 0, 0, 0)
emit("permall", "permute", list(cases))
