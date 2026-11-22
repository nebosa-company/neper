# uwot's find_ab_params (stats::nls Gauss-Newton on 300 points): "ab": args (spread, min_dist, which) with which 0 the a and 1 the b of the fit.
# Tolerance 1e-8 relative: nls stops at a relative offset 1e-5, and numericDeriv divides by a step of 1.5e-8 x, so last-bit pow differences between libms reach about 1e-10 in the fit; the port follows the iteration path step for step.
suppressMessages(library(uwot))
cases <- list()
grid <- expand.grid(spread = c(0.5, 1, 1.5, 2, 3), min_dist = c(0.001, 0.01, 0.1, 0.25, 0.5, 1))
for (i in seq_len(nrow(grid))) {
  sp <- grid$spread[i]; md <- grid$min_dist[i]
  ab <- try(uwot:::find_ab_params(spread = sp, min_dist = md), silent = TRUE)
  if (inherits(ab, "try-error")) next
  for (w in 0:1) cases[[length(cases) + 1]] <- case("ab", c(sp, md, w), ab[w + 1], rel = 1e-8, abs = 1e-12)
}
emit("uwotab", "uwot", list(cases))
