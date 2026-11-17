# vars::stability: the fluctuation processes strucchange::efp builds for every equation of a VAR, and sctest's statistic and closed-form p values.
#   Every case rebuilds its data from the seed as in vars_core. args: (seed, T0, K, p, det, season, nexo, slope, type, eq, h, rescale, functional)
#   type 0 Rec-CUSUM 1 OLS-CUSUM 2 Rec-MOSUM 3 OLS-MOSUM 4 RE 5 ME 6 Score-CUSUM 7 Score-MOSUM 8 fluctuation (RE); functional 0 max 1 range 2 maxL2 3 meanL2
suppressMessages(library(vars))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
H <- 6
gen <- function(seed, T0, K, nexo, slope) {
  set.seed(seed)
  A <- matrix(runif(K * K, -0.3, 0.3), K, K)
  y <- matrix(0, T0, K)
  for (t in 2:T0) y[t, ] <- A %*% y[t - 1, ] + rnorm(K) + slope * t
  colnames(y) <- paste0("s", 1:K)
  exo <- NULL
  if (nexo > 0) { exo <- matrix(rnorm(T0 * nexo), T0, nexo); colnames(exo) <- paste0("e", 1:nexo); rnorm(H * nexo) }
  list(y = y, exo = exo)
}
wsum <- function(m) sum(as.vector(m) * seq_len(length(m)))
types <- c("none", "const", "trend", "both")
mk <- function(d, p, det, season) {
  a <- list(y = d$y, p = p, type = types[det + 1])
  if (season > 0) a$season <- season
  if (!is.null(d$exo)) a$exogen <- d$exo
  do.call(VAR, a)
}
tnames <- c("Rec-CUSUM", "OLS-CUSUM", "Rec-MOSUM", "OLS-MOSUM", "RE", "ME", "Score-CUSUM", "Score-MOSUM", "fluctuation")
fnames <- c("max", "range", "maxL2", "meanL2")
cfgs <- list(c(401, 90, 2, 1, 1, 0, 0, 0), c(402, 110, 3, 2, 1, 0, 0, 0), c(403, 100, 2, 2, 3, 0, 0, 0.02), c(404, 120, 2, 1, 0, 0, 1, 0), c(405, 110, 4, 2, 3, 4, 0, 0))
for (cf in cfgs) {
  seed <- cf[1]; T0 <- cf[2]; K <- cf[3]; p <- cf[4]; det <- cf[5]; season <- cf[6]; nexo <- cf[7]; slope <- cf[8]
  d <- gen(seed, T0, K, nexo, slope); v <- mk(d, p, det, season)
  for (ty in 0:8) for (resc in c(1, 0)) {
    if (resc == 0 && !(ty %in% c(4, 5, 8))) next
    h <- if (ty %in% c(2, 3, 5, 7)) 0.25 else 0.15
    st <- stability(v, type = tnames[ty + 1], h = h, rescale = resc == 1)
    for (e in 1:K) {
      ef <- st$stability[[e]]
      a <- c(cf, ty, e, h, resc, 0)
      add("proc", a, wsum(as.matrix(ef$process)))
      bridge <- ty %in% c(1, 4, 6, 8)
      for (fu in 0:(if (bridge) 3 else 0)) {
        sc <- sctest(ef, functional = fnames[fu + 1])
        add("stat", c(cf, ty, e, h, resc, fu), sc$statistic)
        if (fu <= 1 && (ty %in% c(0, 1, 4, 6, 8)) && (fu == 0 || bridge)) add("pval", c(cf, ty, e, h, resc, fu), sc$p.value)
      }
    }
  }
}
emit("vars_stab", "vars", list(cases))
