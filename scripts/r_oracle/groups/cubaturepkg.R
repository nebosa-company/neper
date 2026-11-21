# cubaturepkg: hcubature and pcubature integrals of four smooth integrands over boxes of dimension 1 to 3.
#   args: (id 0 exp(-sum x^2), 1 prod cos, 2 1/(1+sum x), 3 (sum x)^2 exp(-prod x); d; lo (d); hi (d)). The reference is R at tol 1e-13, compared at rel 1e-11.
suppressMessages(library(cubature))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-13)
fs <- list(function(x) exp(-sum(x^2)), function(x) prod(cos(x)), function(x) 1 / (1 + sum(x)), function(x) sum(x)^2 * exp(-prod(x)))
set.seed(20262013)
for (rep in 1:24) {
  d <- sample(1:3, 1); id <- (rep - 1) %% 4; lo <- runif(d, 0, 0.5); hi <- lo + runif(d, 0.3, 1.2)
  r <- if (rep %% 2 == 0) hcubature(fs[[id + 1]], lo, hi, tol = 1e-10, maxEval = 2e5) else pcubature(fs[[id + 1]], lo, hi, tol = 1e-10, maxEval = 2e5)
  # the reference is R at tol 1e-13 (R's own tolerance, not the module's, bounds the comparison)
  r <- hcubature(fs[[id + 1]], lo, hi, tol = 1e-13, maxEval = 4e6)
  add("box", c(id, d, lo, hi), r$integral)
}
# (the old fixed-integrand infinite-limit comparison is replaced by the exact hcubature and pcubature cases below; the draws stay so the other cases keep their boxes)
for (rep in 1:16) {
  d <- sample(1:2, 1); lo <- numeric(d); hi <- numeric(d)
  for (k in 1:d) { kind <- sample(1:3, 1); if (kind == 1) { lo[k] <- -Inf; hi[k] <- Inf } else if (kind == 2) { lo[k] <- runif(1, -1, 0.5); hi[k] <- Inf } else { lo[k] <- -Inf; hi[k] <- runif(1, -0.5, 1) } }
}
# hcubature's own recursion for 1 to 3 dimensions: "hg" args (id, d, lo[d], hi[d], tol, maxEval, which) with which 0 the integral, 1 the error estimate, 2 the evaluation count, 3 the return code
hgput <- function(a, r) {
  cases[[length(cases) + 1]] <<- case("hg", c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("hg", c(a, 1), r$error, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("hg", c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case("hg", c(a, 3), r$returnCode, rel = 0, abs = 0)
}
for (rep in 1:36) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-4, 1e-6)[1 + (rep %% 3 == 0)]
  r <- hcubature(fs[[id + 1]], lo, hi, tol = tl, maxEval = 20000)
  hgput(c(id, d, lo, hi, tl, 20000), r)
}
# hcubature stopped by maxEval (R still answers return code 0 and the regions summed so far): a small maxEval in 1 to 3 dimensions
sv0 <- .Random.seed; set.seed(20262022)
for (rep in 1:36) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); me <- sample(c(1, 20, 60, 150, 400, 1000, 3000), 1)
  r <- hcubature(fs[[id + 1]], lo, hi, tol = 1e-12, maxEval = me)
  hgput(c(id, d, lo, hi, 1e-12, me), r)
}
assign(".Random.seed", sv0, envir = globalenv())
# pcubature in one dimension (Clenshaw-Curtis): "pc" args (id, 1, lo, hi, tol, maxEval, which) with which 0 the integral, 1 the error estimate, 2 the evaluation count
for (rep in 1:24) {
  id <- (rep - 1) %% 4; lo <- round(runif(1, 0, 0.5), 3); hi <- lo + round(runif(1, 0.4, 1.5), 3); tl <- c(1e-3, 1e-6, 1e-9)[1 + rep %% 3]
  r <- pcubature(fs[[id + 1]], lo, hi, tol = tl, maxEval = 20000)
  if (r$functionEvaluations >= 20000) next
  a <- c(id, 1, lo, hi, tl, 20000)
  cases[[length(cases) + 1]] <- case("pc", c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("pc", c(a, 1), r$error, rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("pc", c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("pc", c(a, 3), r$returnCode, rel = 0, abs = 0)
}
# hcubature with a vector integrand: "hv" args (id, d, lo[d], hi[d], tol, maxEval, which): id 0 (exp(-sum x^2), prod cos x), id 1 (1 / (1 + sum x), (sum x)^2 exp(-prod x), exp(-sum x^2)); which 0 .. nc - 1 the integrals,
# nc .. 2 nc - 1 the error estimates, 2 nc the evaluation count
fv <- list(function(x) c(exp(-sum(x^2)), prod(cos(x))), function(x) c(1 / (1 + sum(x)), sum(x)^2 * exp(-prod(x)), exp(-sum(x^2))))
# which 2 nc + 1 the return code
hvput <- function(a, r, nc, nm = "hv", ab = 1e-12) {
  for (k in 1:nc) { cases[[length(cases) + 1]] <<- case(nm, c(a, k - 1), r$integral[k], rel = 1e-9, abs = 1e-12); cases[[length(cases) + 1]] <<- case(nm, c(a, nc + k - 1), r$error[k], rel = 1e-9, abs = ab) }
  cases[[length(cases) + 1]] <<- case(nm, c(a, 2 * nc), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case(nm, c(a, 2 * nc + 1), r$returnCode, rel = 0, abs = 0)
}
for (rep in 1:20) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-4, 1e-6)[1 + (rep %% 3 == 0)]
  r <- hcubature(fv[[id + 1]], lo, hi, tol = tl, maxEval = 20000, fDim = nc)
  hvput(c(id, d, lo, hi, tl, 20000), r, nc)
}
sv0 <- .Random.seed; set.seed(20262023)
for (rep in 1:20) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); me <- sample(c(1, 20, 60, 150, 400, 1000, 3000), 1)
  r <- hcubature(fv[[id + 1]], lo, hi, tol = 1e-12, maxEval = me, fDim = nc)
  hvput(c(id, d, lo, hi, 1e-12, me), r, nc)
}
assign(".Random.seed", sv0, envir = globalenv())
# pcubature in two and three dimensions: "pn" args (id, d, lo[d], hi[d], tol, which) with which 0 the integral, 1 the error estimate, 2 the evaluation count
for (rep in 1:24) {
  id <- (rep - 1) %% 4; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-3, 1e-5, 1e-7)[1 + rep %% 3]
  r <- pcubature(fs[[id + 1]], lo, hi, tol = tl, maxEval = 1e6)
  if (r$functionEvaluations > 60000) next
  a <- c(id, d, lo, hi, tl, 1e6)
  cases[[length(cases) + 1]] <- case("pn", c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("pn", c(a, 1), r$error, rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("pn", c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("pn", c(a, 3), r$returnCode, rel = 0, abs = 0)
}
# pcubature with a maxEval that stops the run: "pn" with the maxEval in place of 1e6, and "pc" likewise in one dimension (args as above)
for (rep in 1:24) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); me <- sample(c(1, 5, 10, 20, 40, 70, 120, 250), 1)
  r <- pcubature(fs[[id + 1]], lo, hi, tol = 1e-12, maxEval = me)
  a <- c(id, d, lo, hi, 1e-12, me); nm <- if (d == 1) "pc" else "pn"
  cases[[length(cases) + 1]] <- case(nm, c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case(nm, c(a, 1), r$error, rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case(nm, c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case(nm, c(a, 3), r$returnCode, rel = 0, abs = 0)
}
# cuhre (Cuba's DCUHRE rules, final = 1): "ch" args (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, key, which); with nc components which 0 .. nc - 1 the integrals, nc .. 2 nc - 1 the errors,
# 2 nc the evaluations, 2 nc + 1 the regions, 2 nc + 2 .. 3 nc + 1 the chi-square probabilities (abs 2e-2: chisqsum - avg * chisum cancels to rounding noise, so one ulp of libm moves it), 3 nc + 2 the return code. Infinite ends are written +-1e100.
chcase <- function(f, nc, id, vec, lo, hi, rt, at, mn, mx, key) {
  d <- length(lo)
  r <- cuhre(f, nComp = nc, lowerLimit = lo, upperLimit = hi, relTol = rt, absTol = at, minEval = mn, maxEval = mx, key = key)
  # the chi-square probability is chisqsum - avg * chisum, a cancellation to rounding noise: R's own value moves when the integrand is perturbed in the last bits (eight perturbations of 2e-16 to 1e-14).
  # The comparison is abs = 4 times the largest move (at least 1e-7, at most 1) with rel 1e-8; the other quantities are exact
  dp <- rep(0, nc)
  for (pt in list(c(1e-16, 1e9), c(1e-15, 1e9), c(1e-14, 7e8), c(3e-16, 3e9), c(2e-16, 1.3e10), c(5e-16, 4.1e8), c(1e-15, 2.7e11), c(4e-16, 9e7))) {
    r2 <- cuhre(function(x) f(x) * (1 + pt[1] * ((sum(x) * pt[2]) %% 1)), nComp = nc, lowerLimit = lo, upperLimit = hi, relTol = rt, absTol = at, minEval = mn, maxEval = mx, key = key)
    dp <- pmax(dp, abs(r2$prob - r$prob))
  }
  a <- c(id, vec, d, ifelse(lo <= -1e100, -1e100, lo), ifelse(hi >= 1e100, 1e100, hi), rt, at, mn, mx, key)
  put <- function(w, v, rl, ab) cases[[length(cases) + 1]] <<- case("ch", c(a, w), v, rel = rl, abs = ab)
  for (k in 1:nc) { put(k - 1, r$integral[k], 1e-9, 1e-13); put(nc + k - 1, r$error[k], 1e-9, 1e-14); put(2 * nc + 1 + k, r$prob[k], 1e-8, min(1, max(1e-7, 4 * dp[k]))) }
  put(2 * nc, r$neval, 0, 0); put(2 * nc + 1, r$nregions, 0, 0); put(3 * nc + 2, r$returnCode, 0, 0)
}
for (rep in 1:48) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  rt <- c(1e-4, 1e-6, 1e-8)[1 + rep %% 3]; keys <- c(0, 7, 9, if (d == 2) 13, if (d == 3) 11); key <- keys[1 + (rep %/% 4) %% length(keys)]
  mx <- c(1e5, 2000)[1 + (rep %% 8 == 0)]
  chcase(fs[[id + 1]], 1, id, 0, lo, hi, rt, 1e-12, 0, mx, key)
}
for (rep in 1:16) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  chcase(fv[[id + 1]], nc, id, 1, lo, hi, c(1e-4, 1e-6)[1 + rep %% 2], 1e-12, 0, 1e5, 0)
}
for (rep in 1:16) {
  d <- sample(1:2, 1); lo <- numeric(d); hi <- numeric(d)
  for (k in 1:d) { kind <- sample(1:3, 1); if (kind == 1) { lo[k] <- -Inf; hi[k] <- Inf } else if (kind == 2) { lo[k] <- round(runif(1, -1, 0.5), 3); hi[k] <- Inf } else { lo[k] <- -Inf; hi[k] <- round(runif(1, -0.5, 1), 3) } }
  chcase(fs[[1]], 1, 0, 0, lo, hi, c(1e-4, 1e-6)[1 + rep %% 2], 1e-12, 0, 1e5, 0)
}
# vegas (Mersenne Twister, rngSeed as given, final = 1): "vg" args (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, nStart, nIncrease, seed, which); which 0 .. nc - 1 the integrals, nc .. 2 nc - 1 the errors,
# 2 nc the evaluations, 2 nc + 1 .. 3 nc the chi-square probabilities, 3 nc + 1 the return code
vgcase <- function(f, nc, id, vec, lo, hi, rt, at, mn, mx, ns, ni, sd) {
  d <- length(lo)
  r <- vegas(f, nComp = nc, lowerLimit = lo, upperLimit = hi, relTol = rt, absTol = at, minEval = mn, maxEval = mx, nStart = ns, nIncrease = ni, rngSeed = sd)
  a <- c(id, vec, d, ifelse(lo <= -1e100, -1e100, lo), ifelse(hi >= 1e100, 1e100, hi), rt, at, mn, mx, ns, ni, sd)
  put <- function(w, v, rl, ab) cases[[length(cases) + 1]] <<- case("vg", c(a, w), v, rel = rl, abs = ab)
  for (k in 1:nc) { put(k - 1, r$integral[k], 1e-9, 1e-13); put(nc + k - 1, r$error[k], 1e-9, 1e-14); put(2 * nc + k, r$prob[k], 1e-8, 1e-12) }
  put(2 * nc, r$neval, 0, 0); put(3 * nc + 1, r$returnCode, 0, 0)
}
for (rep in 1:24) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  vgcase(fs[[id + 1]], 1, id, 0, lo, hi, c(1e-2, 1e-3, 1e-4)[1 + rep %% 3], 1e-12, 0, c(20000, 6000)[1 + (rep %% 4 == 0)], 1000, 500, c(12345, 7, 2026)[1 + rep %% 3])
}
for (rep in 1:8) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  vgcase(fv[[id + 1]], nc, id, 1, lo, hi, 1e-3, 1e-12, 0, 10000, 800, 400, 12345)
}
for (rep in 1:6) {
  d <- 1 + rep %% 2; lo <- rep(-Inf, d); hi <- rep(Inf, d); if (rep > 3) lo[1] <- round(runif(1, -1, 0.5), 3)
  vgcase(fs[[1]], 1, 0, 0, lo, hi, 1e-3, 1e-12, 0, 8000, 1000, 500, 12345)
}
# suave (Mersenne Twister, rngSeed as given, final = 1; the R result has no region count): "sv" args (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, nNew, nMin, flatness, seed, which); which as for cuhre
svcase <- function(f, nc, id, vec, lo, hi, rt, at, mn, mx, nn, nm, fl, sd) {
  d <- length(lo)
  r <- suave(f, nComp = nc, lowerLimit = lo, upperLimit = hi, relTol = rt, absTol = at, minEval = mn, maxEval = mx, nNew = nn, nMin = nm, flatness = fl, rngSeed = sd)
  a <- c(id, vec, d, ifelse(lo <= -1e100, -1e100, lo), ifelse(hi >= 1e100, 1e100, hi), rt, at, mn, mx, nn, nm, fl, sd)
  put <- function(w, v, rl, ab) cases[[length(cases) + 1]] <<- case("sv", c(a, w), v, rel = rl, abs = ab)
  for (k in 1:nc) { put(k - 1, r$integral[k], 1e-9, 1e-13); put(nc + k - 1, r$error[k], 1e-9, 1e-14); put(2 * nc + 1 + k, r$prob[k], 1e-8, 1e-12) }
  put(2 * nc, r$neval, 0, 0); put(3 * nc + 2, r$returnCode, 0, 0)
}
for (rep in 1:20) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  svcase(fs[[id + 1]], 1, id, 0, lo, hi, c(1e-2, 1e-3)[1 + rep %% 2], 1e-12, 0, c(20000, 8000)[1 + (rep %% 4 == 0)], 500, 2, 25, c(12345, 7, 2026)[1 + rep %% 3])
}
for (rep in 1:6) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  svcase(fv[[id + 1]], nc, id, 1, lo, hi, 1e-2, 1e-12, 0, 10000, 500, 2, 25, 12345)
}
# suave stopped after the first sample (a loose tolerance) and after exactly one split (maxEval = 1000)
for (rep in 1:8) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  svcase(fs[[id + 1]], 1, id, 0, lo, hi, 0.5, 1e-12, 0, 20000, 500, 2, 25, 12345)
  svcase(fs[[id + 1]], 1, id, 0, lo, hi, 1e-9, 1e-12, 0, 1000, 500, 2, 25, 12345)
}
# the Sobol generator (rngSeed 0, suave's default) for vegas and suave, scalar and vector integrands
for (rep in 1:12) {
  id <- (rep - 1) %% 4; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  vgcase(fs[[id + 1]], 1, id, 0, lo, hi, c(1e-3, 1e-4)[1 + rep %% 2], 1e-12, 0, 20000, 1000, 500, 0)
  svcase(fs[[id + 1]], 1, id, 0, lo, hi, c(1e-2, 1e-3)[1 + rep %% 2], 1e-12, 0, 20000, 500, 2, 25, 0)
}
for (rep in 1:4) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  vgcase(fv[[id + 1]], nc, id, 1, lo, hi, 1e-3, 1e-12, 0, 10000, 800, 400, 0)
  svcase(fv[[id + 1]], nc, id, 1, lo, hi, 1e-2, 1e-12, 0, 10000, 500, 2, 25, 0)
}
# infinite limits with a vector integrand (id 2: exp(-sum x^2), (sum x)^2 exp(-sum x^2), exp(-sum x^2) prod cos x) and scalar id 4 ((sum x)^2 exp(-sum x^2)) for cuhre, vegas and suave
fv[[3]] <- function(x) c(exp(-sum(x^2)), sum(x)^2 * exp(-sum(x^2)), exp(-sum(x^2)) * prod(cos(x)))
fs[[5]] <- function(x) sum(x)^2 * exp(-sum(x^2))
infbox <- function() {
  d <- sample(1:2, 1); lo <- numeric(d); hi <- numeric(d)
  for (k in 1:d) { kind <- sample(1:3, 1); if (kind == 1) { lo[k] <- -Inf; hi[k] <- Inf } else if (kind == 2) { lo[k] <- round(runif(1, -1, 0.5), 3); hi[k] <- Inf } else { lo[k] <- -Inf; hi[k] <- round(runif(1, -0.5, 1), 3) } }
  list(d = d, lo = lo, hi = hi)
}
inf1e <- function(v) ifelse(is.infinite(v), sign(v) * 1e100, v)
for (rep in 1:12) {
  b <- infbox()
  chcase(fv[[3]], 3, 2, 1, b$lo, b$hi, c(1e-4, 1e-6)[1 + rep %% 2], 1e-12, 0, 1e5, 0)
  chcase(fs[[5]], 1, 4, 0, b$lo, b$hi, 1e-5, 1e-12, 0, 1e5, 0)
}
for (rep in 1:8) {
  b <- infbox()
  vgcase(fv[[3]], 3, 2, 1, b$lo, b$hi, 1e-3, 1e-12, 0, 8000, 1000, 500, c(12345, 7)[1 + rep %% 2])
  svcase(fv[[3]], 3, 2, 1, b$lo, b$hi, 1e-2, 1e-12, 0, 10000, 500, 2, 25, c(12345, 0)[1 + rep %% 2])
  svcase(fs[[1]], 1, 0, 0, b$lo, b$hi, 1e-2, 1e-12, 0, 10000, 500, 2, 25, c(12345, 0)[1 + rep %% 2])
  vgcase(fs[[5]], 1, 4, 0, b$lo, b$hi, 1e-3, 1e-12, 0, 8000, 1000, 500, 0)
}
# divonne (Korobov samples, final = 1): "dv" args (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, key1, key2, key3, maxPass, border, maxChisq, minDeviation, which); which as for cuhre (no region count: 2 nc + 1 is skipped)
dvcase <- function(f, nc, id, vec, lo, hi, rt, at, mn, mx, k1 = 47, k2 = 1, k3 = 1, mp = 5, bd = 0, mc = 10, md = 0.25) {
  d <- length(lo)
  dv <- function(g) divonne(g, nComp = nc, lowerLimit = lo, upperLimit = hi, relTol = rt, absTol = at, minEval = mn, maxEval = mx, key1 = k1, key2 = k2, key3 = k3, maxPass = mp, border = bd, maxChisq = mc, minDeviation = md)
  r <- dv(f)
  # Divonne's partitioning follows an optimiser whose steps compare function values: a libm that differs in the last bit can move one step, which leaves the integral (Korobov samples of a fixed partition) alone
  # but moves the evaluation count by a few and the error estimate in its sixth digit. A case whose own R result moves when the integrand is perturbed by 1e-15 gets those two loosened (stated here, once); the others are exact.
  r2 <- dv(function(x) f(x) * (1 + 1e-15 * ((sum(x) * 1e9) %% 1)))
  r3 <- dv(function(x) f(x) * (1 + 1e-14 * ((sum(x) * 7e8) %% 1)))
  stable <- r2$neval == r$neval && all(abs(r2$error - r$error) <= 1e-9 * abs(r$error)) && all(abs(r2$integral - r$integral) <= 1e-9 * abs(r$integral)) && r3$neval == r$neval && all(abs(r3$error - r$error) <= 1e-9 * abs(r$error))
  a <- c(id, vec, d, ifelse(lo <= -1e100, -1e100, lo), ifelse(hi >= 1e100, 1e100, hi), rt, at, mn, mx, k1, k2, k3, mp, bd, mc, md)
  put <- function(w, v, rl, ab) cases[[length(cases) + 1]] <<- case("dv", c(a, w), v, rel = rl, abs = ab)
  for (k in 1:nc) { put(k - 1, r$integral[k], 1e-9, 1e-13); put(nc + k - 1, r$error[k], if (stable) 1e-9 else 1e-5, 1e-14); put(2 * nc + 1 + k, r$prob[k], 1e-8, 2e-2) }
  put(2 * nc, r$neval, 0, if (stable) 0 else ceiling(0.002 * r$neval) + 3); put(3 * nc + 2, r$returnCode, 0, if (!stable && abs(r$returnCode) > 10) ceiling(0.01 * abs(r$returnCode)) else 0)
}
set.seed(20262020)
for (rep in 1:16) {
  id <- (rep - 1) %% 4; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  dvcase(fs[[id + 1]], 1, id, 0, lo, hi, c(1e-3, 1e-5)[1 + rep %% 2], 1e-12, 0, 100000)
}
# divonne across its parameters: key1 and key2 as multiplicators and point counts, key3 0 / 1 / a sample count, maxPass, a border, a tight maxEval (return codes and -999 probabilities), vector integrands, infinite limits
for (rep in 1:48) {
  id <- (rep - 1) %% 4; d <- 2 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  k1 <- c(47, 100, 200, 60)[1 + (rep %/% 4) %% 4]; k2 <- c(1, 5, 100, 1, 2, 1)[1 + (rep %/% 2) %% 6]; k3 <- c(1, 0, 1, 47, 1, 100)[1 + (rep %/% 3) %% 6]
  dvcase(fs[[id + 1]], 1, id, 0, lo, hi, c(1e-3, 1e-4, 1e-5)[1 + rep %% 3], 1e-12, 0, c(100000, 3000)[1 + (rep %% 7 == 0)], k1, k2, k3, c(5, 2, 8)[1 + rep %% 3])
}
for (rep in 1:8) {
  id <- (rep - 1) %% 4; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  dvcase(fs[[id + 1]], 1, id, 0, lo, hi, 1e-4, 1e-12, 0, 100000, bd = c(0.05, 0.1)[1 + rep %% 2])
}
for (rep in 1:12) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  dvcase(fv[[id + 1]], nc, id, 1, lo, hi, c(1e-3, 1e-4)[1 + rep %% 2], 1e-12, 0, 100000)
}
for (rep in 1:12) {
  d <- 2; lo <- numeric(d); hi <- numeric(d)
  for (k in 1:d) { kind <- sample(1:3, 1); if (kind == 1) { lo[k] <- -Inf; hi[k] <- Inf } else if (kind == 2) { lo[k] <- round(runif(1, -1, 0.5), 3); hi[k] <- Inf } else { lo[k] <- -Inf; hi[k] <- round(runif(1, -0.5, 1), 3) } }
  if (rep %% 2 == 0) dvcase(fs[[1]], 1, 0, 0, lo, hi, 1e-4, 1e-12, 0, 100000) else dvcase(fv[[3]], 3, 2, 1, lo, hi, 1e-3, 1e-12, 0, 100000)
}
# infinite limits for hcubature and pcubature (R maps them through tan: the integrand ids + 100 over atan(lo) .. atan(hi)), scalar and vector integrands, and the vector pcubature on finite boxes: "pv" args (id, d, lo[d], hi[d], tol, maxEval, which)
# with which 0 .. nc - 1 the integrals, nc .. 2 nc - 1 the errors, 2 nc the evaluations
set.seed(20262021)
fi <- list(fs[[1]], fs[[5]]); fiid <- c(0, 4)
for (rep in 1:30) {
  b <- infbox(); d <- b$d + (rep %% 3 == 0); if (d > b$d) { b$lo <- c(b$lo, -Inf); b$hi <- c(b$hi, Inf) }
  id <- 1 + rep %% 2; tl <- c(1e-4, 1e-6)[1 + (rep %% 4 > 1)]
  r <- hcubature(fi[[id]], b$lo, b$hi, tol = tl, maxEval = 40000)
  a <- c(fiid[id] + 100, d, atan(b$lo), atan(b$hi), tl, 40000)
  if (r$functionEvaluations < 40000) hgput(a, r)
  r <- pcubature(fi[[id]], b$lo, b$hi, tol = tl, maxEval = 40000)
  nm <- if (d == 1) "pc" else "pn"
  if (r$functionEvaluations > 60000) next
  cases[[length(cases) + 1]] <- case(nm, c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case(nm, c(a, 1), r$error, rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case(nm, c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case(nm, c(a, 3), r$returnCode, rel = 0, abs = 0)
}
for (rep in 1:16) {
  b <- infbox(); d <- b$d + (rep %% 3 == 0); if (d > b$d) { b$lo <- c(b$lo, -Inf); b$hi <- c(b$hi, Inf) }
  tl <- c(1e-4, 1e-6)[1 + (rep %% 4 > 1)]
  r <- hcubature(fv[[3]], b$lo, b$hi, tol = tl, maxEval = 40000, fDim = 3)
  a <- c(102, d, atan(b$lo), atan(b$hi), tl, 40000)
  if (r$functionEvaluations < 40000) hvput(a, r, 3)
  r <- pcubature(fv[[3]], b$lo, b$hi, tol = tl, maxEval = 40000, fDim = 3)
  if (r$functionEvaluations > 60000) next
  hvput(a, r, 3, "pv", 1e-13)
}
for (rep in 1:20) {
  id <- (rep - 1) %% 2; nc <- c(2, 3)[id + 1]; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-3, 1e-5, 1e-7)[1 + rep %% 3]
  me <- c(1e6, 200)[1 + (rep %% 5 == 0)]
  r <- pcubature(fv[[id + 1]], lo, hi, tol = tl, maxEval = me, fDim = nc)
  if (r$functionEvaluations > 60000) next
  hvput(c(id, d, lo, hi, tl, me), r, nc, "pv", 1e-13)
}
# stress integrands (ids 5 to 9: a narrow peak, a kink, an oscillation, a step, a corner root) so the adaptive splitting of every method is exercised on more than smooth functions
gs <- list(function(x) exp(-50 * sum((x - 0.5)^2)), function(x) sum(abs(x - 0.6)), function(x) sin(8 * sum(x)), function(x) as.numeric(sum(x) < 1), function(x) sqrt(sum(x)))
set.seed(20262030)
for (rep in 1:30) {
  id <- 5 + (rep - 1) %% 5; d <- 1 + (rep %/% 5) %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-4, 1e-6)[1 + rep %% 2]
  r <- hcubature(gs[[id - 4]], lo, hi, tol = tl, maxEval = 20000)
  hgput(c(id, d, lo, hi, tl, 20000), r)
  me <- sample(c(1, 20, 150, 1000), 1)
  r <- hcubature(gs[[id - 4]], lo, hi, tol = 1e-12, maxEval = me)
  hgput(c(id, d, lo, hi, 1e-12, me), r)
}
for (rep in 1:30) {
  id <- 5 + (rep - 1) %% 5; d <- 1 + (rep %/% 5) %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-3, 1e-5)[1 + rep %% 2]
  r <- pcubature(gs[[id - 4]], lo, hi, tol = tl, maxEval = 100000)
  nm <- if (d == 1) "pc" else "pn"
  if (r$functionEvaluations <= 60000) {
    a <- c(id, d, lo, hi, tl, 100000)
    cases[[length(cases) + 1]] <- case(nm, c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case(nm, c(a, 1), r$error, rel = 1e-9, abs = 1e-13)
    cases[[length(cases) + 1]] <- case(nm, c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case(nm, c(a, 3), r$returnCode, rel = 0, abs = 0)
  }
  me <- sample(c(1, 10, 60, 300), 1)
  r <- pcubature(gs[[id - 4]], lo, hi, tol = 1e-12, maxEval = me)
  a <- c(id, d, lo, hi, 1e-12, me)
  cases[[length(cases) + 1]] <- case(nm, c(a, 0), r$integral, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case(nm, c(a, 1), r$error, rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case(nm, c(a, 2), r$functionEvaluations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case(nm, c(a, 3), r$returnCode, rel = 0, abs = 0)
}
for (rep in 1:20) {
  id <- 5 + (rep - 1) %% 5; d <- 1 + (rep %/% 5) %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  keys <- c(0, 7, 9, if (d == 2) 13, if (d == 3) 11); key <- keys[1 + (rep %/% 3) %% length(keys)]
  chcase(gs[[id - 4]], 1, id, 0, lo, hi, c(1e-3, 1e-5)[1 + rep %% 2], 1e-12, 0, 1e5, key)
}
for (rep in 1:15) {
  id <- 5 + (rep - 1) %% 5; d <- 1 + (rep %/% 5) %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  vgcase(gs[[id - 4]], 1, id, 0, lo, hi, 1e-2, 1e-12, 0, 20000, 1000, 500, c(12345, 7, 0)[1 + rep %% 3])
  svcase(gs[[id - 4]], 1, id, 0, lo, hi, 1e-2, 1e-12, 0, 20000, 500, 2, 25, c(12345, 7, 0)[1 + rep %% 3])
}
for (rep in 1:15) {
  id <- 5 + (rep - 1) %% 5; d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
  dvcase(gs[[id - 4]], 1, id, 0, lo, hi, c(1e-3, 1e-4)[1 + rep %% 2], 1e-12, 0, 100000)
}
# user integrands the module does not hard-code: the fixture registers them with set_user (ids 1000 to 1003; 1100 + k is the same function through the tan map). Sums run in double in a loop on both sides.
# u0 (1 + s) sin(3 q) exp(-0.3 s), u1 (s^2 cos q, exp(-s) / (1 + q)), u2 exp(-q) (2 + sin s), u3 (exp(-q) (2 + sin s), exp(-q) cos s) with s the sum and q the sum of squares
sq <- function(x) { s <- 0; q <- 0; for (v in x) { s <- s + v; q <- q + v * v }; c(s, q) }
us <- list(function(x) { w <- sq(x); (1 + w[1]) * sin(3 * w[2]) * exp(-0.3 * w[1]) },
           function(x) { w <- sq(x); c(w[1] * w[1] * cos(w[2]), exp(-w[1]) / (1 + w[2])) },
           function(x) { w <- sq(x); exp(-w[2]) * (2 + sin(w[1])) },
           function(x) { w <- sq(x); c(exp(-w[2]) * (2 + sin(w[1])), exp(-w[2]) * cos(w[1])) })
unc <- c(1, 2, 1, 2)
set.seed(20262040)
for (rep in 1:30) {
  k <- c(1, 2)[1 + rep %% 2]; nc <- unc[k]; d <- 1 + rep %% 3; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3); tl <- c(1e-4, 1e-6, 1e-8)[1 + rep %% 3]
  if (nc == 1) { r <- hcubature(us[[k]], lo, hi, tol = tl, maxEval = 40000); if (r$functionEvaluations < 40000) hgput(c(999 + k, d, lo, hi, tl, 40000), r)
    r <- pcubature(us[[k]], lo, hi, tol = tl, maxEval = 100000); nm <- if (d == 1) "pc" else "pn"
    if (r$functionEvaluations <= 60000) { a <- c(999 + k, d, lo, hi, tl, 100000); for (w in 0:3) cases[[length(cases) + 1]] <- case(nm, c(a, w), c(r$integral, r$error, r$functionEvaluations, r$returnCode)[w + 1], rel = if (w < 2) 1e-9 else 0, abs = c(1e-12, 1e-13, 0, 0)[w + 1]) } }
  else { d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3)
    r <- hcubature(us[[k]], lo, hi, tol = tl, maxEval = 40000, fDim = nc); if (r$functionEvaluations < 40000) hvput(c(999 + k, d, lo, hi, tl, 40000), r, nc)
    r <- pcubature(us[[k]], lo, hi, tol = tl, maxEval = 100000, fDim = nc); if (r$functionEvaluations <= 60000) hvput(c(999 + k, d, lo, hi, tl, 100000), r, nc, "pv", 1e-13) }
}
# a user integrand with infinite limits for hcubature and pcubature (ids 1100 + k over atan(lo) .. atan(hi))
for (rep in 1:20) {
  b <- infbox(); k <- c(3, 4)[1 + rep %% 2]; nc <- unc[k]; tl <- c(1e-4, 1e-6)[1 + (rep %% 4 > 1)]
  a <- c(1099 + k, b$d, atan(b$lo), atan(b$hi), tl, 40000)
  if (nc == 1) {
    r <- hcubature(us[[k]], b$lo, b$hi, tol = tl, maxEval = 40000); if (r$functionEvaluations < 40000) hgput(a, r)
    r <- pcubature(us[[k]], b$lo, b$hi, tol = tl, maxEval = 40000); nm <- if (b$d == 1) "pc" else "pn"
    if (r$functionEvaluations <= 60000) for (w in 0:3) cases[[length(cases) + 1]] <- case(nm, c(a, w), c(r$integral, r$error, r$functionEvaluations, r$returnCode)[w + 1], rel = if (w < 2) 1e-9 else 0, abs = c(1e-12, 1e-13, 0, 0)[w + 1])
  } else {
    r <- hcubature(us[[k]], b$lo, b$hi, tol = tl, maxEval = 40000, fDim = nc); if (r$functionEvaluations < 40000) hvput(a, r, nc)
    r <- pcubature(us[[k]], b$lo, b$hi, tol = tl, maxEval = 40000, fDim = nc); if (r$functionEvaluations <= 60000) hvput(a, r, nc, "pv", 1e-13)
  }
}
# the Cuba methods on user integrands (finite and infinite boxes)
for (rep in 1:12) {
  k <- 1 + rep %% 4; nc <- unc[k]; vec <- as.numeric(nc > 1); id <- 999 + k
  if (k <= 2) { d <- 2 + rep %% 2; lo <- round(runif(d, 0, 0.5), 3); hi <- lo + round(runif(d, 0.4, 1.5), 3) } else { b <- infbox(); d <- b$d; lo <- b$lo; hi <- b$hi }
  chcase(us[[k]], nc, id, vec, lo, hi, c(1e-4, 1e-6)[1 + rep %% 2], 1e-12, 0, 1e5, 0)
  vgcase(us[[k]], nc, id, vec, lo, hi, 1e-3, 1e-12, 0, 10000, 800, 400, c(12345, 7, 0)[1 + rep %% 3])
  svcase(us[[k]], nc, id, vec, lo, hi, 1e-2, 1e-12, 0, 10000, 500, 2, 25, c(12345, 0)[1 + rep %% 2])
  if (d >= 2) dvcase(us[[k]], nc, id, vec, lo, hi, 1e-3, 1e-12, 0, 100000)
}
emit("cubaturepkg", "cubature", list(cases))
# the reason for every loosened tolerance, stored in the oracle meta (cases not named here are exact: integers equal, reals at rel 1e-9)
loose <- paste0('"loose":{"ch":"the chi-square probability (chisqsum - avg * chisum) is a cancellation to rounding noise; abs is 4 times the largest move of R own value under eight perturbed integrands (2e-16 to 1e-14), rel 1e-8; every other cuhre quantity is exact or rel 1e-9",',
  '"dv":"divonne partitioning follows an optimiser whose steps compare function values: a case whose own R result moves under a 1e-15 or 1e-14 perturbed integrand gets error rel 1e-5 and the evaluation count a 0.2 percent allowance; the chi-square probability is abs 0.02; stable cases are exact",',
  '"vg_sv":"seeded draws equal R (Mersenne Twister, same seed), rel 1e-9"}')
pth <- file.path(out_dir, "cubaturepkg.json"); ln <- readLines(pth, warn = FALSE, encoding = "UTF-8")
ln[1] <- sub("}}", paste0("},", loose, "}"), ln[1], fixed = TRUE); writeLines(ln, pth, useBytes = TRUE)
