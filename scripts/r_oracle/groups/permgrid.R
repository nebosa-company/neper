# permute: shuffle with grid restrictions (within and plots) under set.seed.
#   args: (seed, n, plot_type 0 free 1 series 2 none 3 grid, plot_mirror, plot_nrow, plot_ncol, plot_sym, within_type 0 free 1 series 2 none 3 grid,
#          within_mirror, within_nrow, within_ncol, within_sym, constant, has_plots, plots[n] (zeros when absent), pos)
suppressMessages(library(permute))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("grid", args, want, rel = 0, abs = 0)
tn <- c("free", "series", "none", "grid")
set.seed(20261118)
run <- function(n, plots, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst) {
  w <- if (wt == 3) Within(type = "grid", mirror = wm == 1, nrow = wr, ncol = wc, symmetric = ws == 1, constant = cst == 1) else Within(type = tn[wt + 1], mirror = wm == 1, constant = cst == 1)
  pl <- if (is.null(plots)) Plots() else if (pt == 3) Plots(strata = factor(plots), type = "grid", mirror = pm == 1, nrow = pr, ncol = pc, symmetric = ps == 1) else Plots(strata = factor(plots), type = tn[pt + 1], mirror = pm == 1)
  how(within = w, plots = pl, nperm = 1)
}
emitcase <- function(n, plots, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst) {
  ctl <- tryCatch(suppressWarnings(run(n, plots, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst)), error = function(e) NULL)
  if (is.null(ctl)) return(invisible())
  seed <- sample(1e6, 1); set.seed(seed)
  r <- tryCatch(suppressWarnings(shuffle(n, ctl)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  a <- c(seed, n, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, !is.null(plots), if (is.null(plots)) rep(0, n) else plots)
  for (i in seq_len(n)) add(c(a, i - 1), r[i])
}
# a grid within a single plot of nrow * ncol observations
for (dm in list(c(3, 4), c(4, 4), c(5, 3), c(2, 6), c(3, 3))) for (wm in 0:1) for (ws in 0:1) for (rep in 1:3)
  emitcase(dm[1] * dm[2], NULL, 0, 0, 0, 0, 0, 3, wm, dm[1], dm[2], ws, 0)
# grid within every plot, with the plots permuted (free, series, none) or not
for (dm in list(c(2, 3), c(3, 3), c(2, 4))) for (np in c(2, 3, 4)) for (wm in 0:1) for (ws in 0:1) for (cst in 0:1) for (pt in c(0, 1, 2)) {
  n <- dm[1] * dm[2] * np; plots <- rep(seq_len(np), each = dm[1] * dm[2])
  emitcase(n, plots, pt, 0, 0, 0, 0, 3, wm, dm[1], dm[2], ws, cst)
}
# the plots on a grid, the observations within free, series, none or grid
for (pg in list(c(2, 3), c(3, 3), c(2, 2), c(4, 3))) for (pm in 0:1) for (ps in 0:1) for (wt in c(0, 1, 2)) for (cst in 0:1) {
  np <- pg[1] * pg[2]; per <- 3; n <- np * per; plots <- rep(seq_len(np), each = per)
  emitcase(n, plots, 3, pm, pg[1], pg[2], ps, wt, 0, 0, 0, 0, cst)
}
for (pg in list(c(2, 3), c(3, 2))) for (pm in 0:1) for (ps in 0:1) for (wm in 0:1) for (ws in 0:1) {
  np <- pg[1] * pg[2]; per <- 6; n <- np * per; plots <- rep(seq_len(np), each = per)
  emitcase(n, plots, 3, pm, pg[1], pg[2], ps, 3, wm, 2, 3, ws, 0)
}
# numPerms of the same designs: fn "gnp", args as above without the position
npcase <- function(n, plots, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst) {
  ctl <- tryCatch(suppressWarnings(run(n, plots, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst)), error = function(e) NULL)
  if (is.null(ctl)) return(invisible())
  v <- tryCatch(suppressWarnings(numPerms(n, ctl, check = FALSE)), error = function(e) NULL)
  if (is.null(v) || !is.finite(v)) return(invisible())
  a <- c(0, n, pt, pm, pr, pc, ps, wt, wm, wr, wc, ws, cst, !is.null(plots), if (is.null(plots)) rep(0, n) else plots)
  cases[[length(cases) + 1]] <<- case("gnp", a, v, rel = 1e-12, abs = 0)
}
for (dm in list(c(3, 4), c(4, 4), c(5, 3), c(2, 6), c(3, 3), c(2, 2))) for (wm in 0:1) for (ws in 0:1) npcase(dm[1] * dm[2], NULL, 0, 0, 0, 0, 0, 3, wm, dm[1], dm[2], ws, 0)
for (dm in list(c(2, 3), c(3, 3), c(2, 4), c(4, 4))) for (np in c(2, 3, 4)) for (wm in 0:1) for (ws in 0:1) for (cst in 0:1) for (pt in c(0, 1, 2)) {
  npcase(dm[1] * dm[2] * np, rep(seq_len(np), each = dm[1] * dm[2]), pt, 0, 0, 0, 0, 3, wm, dm[1], dm[2], ws, cst)
}
for (pg in list(c(2, 3), c(3, 3), c(2, 2), c(4, 3), c(5, 3))) for (pm in 0:1) for (ps in 0:1) for (wt in c(0, 1, 2)) for (cst in 0:1) {
  np <- pg[1] * pg[2]; npcase(np * 3, rep(seq_len(np), each = 3), 3, pm, pg[1], pg[2], ps, wt, 0, 0, 0, 0, cst)
}
for (pg in list(c(2, 3), c(3, 2), c(4, 4))) for (pm in 0:1) for (ps in 0:1) for (wm in 0:1) for (ws in 0:1) {
  np <- pg[1] * pg[2]; npcase(np * 6, rep(seq_len(np), each = 6), 3, pm, pg[1], pg[2], ps, 3, wm, 2, 3, ws, 0)
}
emit("permgrid", "permute", list(cases))
