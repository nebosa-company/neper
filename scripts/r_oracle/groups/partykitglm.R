# partykit glmtree with the families binomial, poisson, gaussian, quasibinomial and quasipoisson, case weights, an offset and clusters (vcov opg).
#   args: (sel, n, kx, pz, alpha, bonf, minsize, maxdepth, trim, fam, usew, useoff, usecl, nl[pz], w[n], off[n], cl[n], xr[n*kx], z[n*pz], y[n])
#   fam 1 binomial, 2 poisson, 3 gaussian, 4 quasibinomial, 5 quasipoisson; usew/useoff/usecl 1 when the weights, offset, cluster are passed (w positive integers, cl codes 0..C-1);
#   nl[j] 0 numeric partitioning variable, L unordered factor with codes 0..L-1
#   sel 1 node count, 2 sum id*zvar, 3 sum id*split, 4 sum id*nobs, 5 sum id*p.value over inner nodes, 6 sum id*sum_j j*coef_j, 7 sum id*objfun, 9 sum row*node id,
#       10 sum id*sum of the instability statistics, 11 sum id*sum of the adjusted p values (NA as 0)
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261503)
fams <- list(binomial(), poisson(), gaussian(), quasibinomial(), quasipoisson())
run <- function(n, kx, pz, nl, alpha, bonf, minsize, maxdepth, trim, fam, usew, useoff, usecl, ncl = 4) {
  Z <- lapply(seq_len(pz), function(j) if (nl[j] == 0) round(rnorm(n) * 5, if (j == 1) 0 else 1) else sample(0:(nl[j] - 1), n, TRUE))
  X <- lapply(seq_len(kx), function(j) round(rnorm(n) * 1, 1))
  g1 <- if (nl[1] == 0) as.numeric(Z[[1]] > median(Z[[1]])) else as.numeric(Z[[1]] %% 2)
  g2 <- if (pz >= 2) (if (nl[2] == 0) as.numeric(Z[[2]] > median(Z[[2]])) else as.numeric(Z[[2]] %% 2)) else 0
  w <- if (usew) sample(1:3, n, TRUE) else rep(1, n)
  off <- if (useoff) round(rnorm(n) * 0.3, 2) else rep(0, n)
  cl <- if (usecl) sample(0:(ncl - 1), n, TRUE) else rep(0, n)
  eta <- -0.3 + 1.2 * g1 - 0.8 * g2
  for (j in seq_len(kx)) eta <- eta + (0.5 + 1.0 * g1 * (j == 1)) * X[[j]] * 0.6
  y <- switch(fam,
    as.numeric(runif(n) < plogis(eta + off)),
    rpois(n, exp(0.3 * eta + off)),
    round(eta + off + rnorm(n) * 1.2, 2),
    as.numeric(runif(n) < plogis(eta + off)),
    rpois(n, exp(0.3 * eta + off)))
  df <- data.frame(y = y)
  for (j in seq_len(kx)) df[[paste0("x", j)]] <- X[[j]]
  for (j in seq_len(pz)) df[[paste0("z", j)]] <- if (nl[j] == 0) Z[[j]] else factor(Z[[j]], levels = 0:(nl[j] - 1))
  df$w <- w; df$off <- off; df$cl <- factor(cl)
  fml <- as.formula(paste("y ~", if (kx > 0) paste0("x", seq_len(kx), collapse = " + ") else "1", "|", paste0("z", seq_len(pz), collapse = " + ")))
  mc <- list(alpha = alpha, bonferroni = bonf, maxdepth = if (maxdepth >= 1000) Inf else maxdepth, trim = trim)
  if (minsize > 0) mc$minsize <- minsize
  args <- list(formula = fml, data = df, family = fams[[fam]])
  args <- c(args, mc)
  if (usew) args$weights <- quote(w)
  if (useoff) args$offset <- quote(off)
  if (usecl) args$cluster <- quote(cl)
  t <- suppressWarnings(do.call(glmtree, args))
  ids <- nodeids(t)
  nodes <- nodeapply(t, ids, function(nd) nd)
  vid <- brk <- nob <- pv <- cs <- of <- st <- ap <- numeric(length(ids))
  for (i in seq_along(ids)) {
    nd <- nodes[[i]]; inf <- info_node(nd)
    nob[i] <- inf$nobs; of[i] <- inf$objfun; cs[i] <- sum(seq_along(inf$coefficients) * inf$coefficients)
    if (!is.null(inf$test)) { s <- inf$test["statistic", ]; st[i] <- sum(ifelse(is.na(s), 0, s)); a <- inf$test["p.value", ]; ap[i] <- sum(ifelse(is.na(a), 0, a)) }
    if (!is.terminal(nd)) {
      sp <- split_node(nd)
      vid[i] <- varid_split(sp) - 1 - kx
      pv[i] <- inf$p.value
      if (nl[vid[i]] == 0) brk[i] <- breaks_split(sp)
      else { ix <- index_split(sp); brk[i] <- sum(seq_along(ix) * ifelse(is.na(ix), 0, ix)) }
    }
  }
  pn <- predict(t, newdata = df, type = "node")
  a0 <- c(n, kx, pz, alpha, bonf, minsize, maxdepth, trim, fam, as.numeric(usew), as.numeric(useoff), as.numeric(usecl), nl, w, off, cl, unlist(X), unlist(Z), y)
  add("lo", c(1, a0), length(ids)); add("lo", c(2, a0), sum(ids * vid)); add("lo", c(3, a0), sum(ids * brk))
  add("lo", c(4, a0), sum(ids * nob)); add("lo", c(5, a0), sum(ids * pv)); add("lo", c(6, a0), sum(ids * cs))
  add("lo", c(7, a0), sum(ids * of)); add("lo", c(9, a0), sum(seq_len(n) * pn))
  add("lo", c(10, a0), sum(ids * st)); add("lo", c(11, a0), sum(ids * ap))
}
# every 6th run is generated (so the random stream is unchanged) but not emitted: keeps the oracle file under 2 MB
run0 <- run; ri <- 0
run <- function(...) { n0 <- length(cases); ri <<- ri + 1; run0(...); if (ri %% 6 == 0) cases <<- cases[seq_len(n0)] }
rep_i <- 0
for (fam in 1:5) for (usew in c(FALSE, TRUE)) for (useoff in c(FALSE, TRUE)) for (usecl in c(FALSE, TRUE)) {
  rep_i <- rep_i + 1
  n <- sample(90:140, 1); kx <- sample(0:2, 1); pz <- sample(2:3, 1)
  nl <- sapply(seq_len(pz), function(j) if (rep_i %% 3 == 0) sample(c(0, 3, 4), 1) else sample(c(0, 0, 2, 3), 1))
  run(n, kx, pz, nl, alpha = c(0.05, 0.2, 0.1)[(rep_i %% 3) + 1], bonf = rep_i %% 3 != 1, minsize = c(0, 10)[(rep_i %% 2) + 1],
      maxdepth = c(1000, 3)[(rep_i %% 2) + 1], trim = c(0.1, 0.2)[(rep_i %% 2) + 1], fam = fam, usew = usew, useoff = useoff, usecl = usecl)
}
emit("partykitglm", "partykit", list(cases))
