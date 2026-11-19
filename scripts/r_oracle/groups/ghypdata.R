# ghypdata: GeneralizedHyperbolic's parameter data sets (e.algo.stat.ghypdata).
# "pset": (family 0 ghyp / 1 hyperb / 2 nig / 3 gig, set 0 LargeParam / 1 SmallParam / 2 LargeShape / 3 SmallShape (gig: 0 Large, 1 Small), row, column), 0-based;
# every row of the small sets and every 9th row of the large ones; "psetrows": (family, set, 0, 0) the number of rows.
suppressMessages(library(GeneralizedHyperbolic))
cases <- list()
sets <- list(list(ghypLargeParam, ghypSmallParam, ghypLargeShape, ghypSmallShape),
             list(hyperbLargeParam, hyperbSmallParam, hyperbLargeShape, hyperbSmallShape),
             list(nigLargeParam, nigSmallParam, nigLargeShape, nigSmallShape),
             list(gigLargeParam, gigSmallParam))
for (f in 1:4) for (s in seq_along(sets[[f]])) {
  m <- sets[[f]][[s]]
  cases[[length(cases) + 1]] <- case("psetrows", c(f - 1, s - 1, 0, 0), nrow(m), rel = 0, abs = 0)
  step <- if (nrow(m) > 200) 9 else 1
  for (r in seq(1, nrow(m), by = step)) for (cc in seq_len(ncol(m)))
    cases[[length(cases) + 1]] <- case("pset", c(f - 1, s - 1, r - 1, cc - 1), m[r, cc], rel = 1e-14, abs = 1e-15)
}
emit("ghypdata", "GeneralizedHyperbolic", list(cases))
