# partykit lmtree with ordered partitioning factors (ordinal = "chisq"), mtry and breakties on set.seed(seed)'s stream.
#   args: (sel, n, kx, pz, alpha, bonf, minsize, maxdepth, trim, vc, mtry, bties, seed, nl[pz], xr[n*kx], z[n*pz], y[n])
#   nl[j] 0 numeric partitioning variable, L unordered factor with codes 0..L-1, -L ordered factor with codes 0..L-1; mtry 0 means Inf; vc 0 opg, 1 info, 2 sandwich
#   sel 1 node count, 2 sum id*zvar, 3 sum id*split (numeric break, ordered level index, or sum (level+1)*child), 4 sum id*nobs, 5 sum id*p.value over inner nodes, 6 sum id*sum_j j*coef_j,
#       7 sum id*objfun, 9 sum row*node id, 10 sum id*sum of the instability statistics, 11 sum id*sum of the adjusted p values (NA as 0)
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261477)
run <- function(n, kx, pz, nl, alpha, bonf, minsize, maxdepth, trim, vc, mtry, bties, seed, noise = 1.5) {
  Z <- lapply(seq_len(pz), function(j) if (nl[j] == 0) round(rnorm(n) * 5, if (j == 1) 0 else 1) else sample(0:(abs(nl[j]) - 1), n, TRUE))
  X <- lapply(seq_len(kx), function(j) round(rnorm(n) * 3, 1))
  sg <- function(j) if (nl[j] == 0) as.numeric(Z[[j]] > median(Z[[j]])) else if (nl[j] < 0) as.numeric(Z[[j]] > (abs(nl[j]) - 1) / 2) else as.numeric(Z[[j]] %% 2)
  g1 <- sg(1)
  g2 <- if (pz >= 2) sg(2) else 0
  eta <- 1 + 3 * g1 + 2 * g2
  for (j in seq_len(kx)) eta <- eta + (1 + 2 * g1 * (j == 1)) * X[[j]]
  y <- round(eta + rnorm(n) * noise, 2)
  df <- data.frame(y = y)
  for (j in seq_len(kx)) df[[paste0("x", j)]] <- X[[j]]
  for (j in seq_len(pz)) df[[paste0("z", j)]] <- if (nl[j] == 0) Z[[j]] else factor(Z[[j]], levels = 0:(abs(nl[j]) - 1), ordered = nl[j] < 0)
  fml <- as.formula(paste("y ~", if (kx > 0) paste0("x", seq_len(kx), collapse = " + ") else "1", "|", paste0("z", seq_len(pz), collapse = " + ")))
  mc <- list(alpha = alpha, bonferroni = bonf, maxdepth = if (maxdepth >= 1000) Inf else maxdepth, trim = trim, vcov = c("opg", "info", "sandwich")[vc + 1],
             mtry = if (mtry == 0) Inf else mtry, breakties = bties)
  if (minsize > 0) mc$minsize <- minsize
  set.seed(seed)
  t <- mob(fml, data = df, fit = partykit:::lmfit, control = do.call(mob_control, mc))
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
      if (nl[vid[i]] <= 0) brk[i] <- breaks_split(sp)
      else { ix <- index_split(sp); brk[i] <- sum(seq_along(ix) * ifelse(is.na(ix), 0, ix)) }
    }
  }
  pn <- predict(t, newdata = df, type = "node")
  a0 <- c(n, kx, pz, alpha, bonf, minsize, maxdepth, trim, vc, mtry, bties, seed, nl, unlist(X), unlist(Z), y)
  add("lx", c(1, a0), length(ids)); add("lx", c(2, a0), sum(ids * vid)); add("lx", c(3, a0), sum(ids * brk))
  add("lx", c(4, a0), sum(ids * nob)); add("lx", c(5, a0), sum(ids * pv)); add("lx", c(6, a0), sum(ids * cs))
  add("lx", c(7, a0), sum(ids * of)); add("lx", c(9, a0), sum(seq_len(n) * pn))
  add("lx", c(10, a0), sum(ids * st)); add("lx", c(11, a0), sum(ids * ap))
}
# every 6th run is generated (so the random stream is unchanged) but not emitted: keeps the oracle file under 2 MB
run0 <- run; ri <- 0
run <- function(...) { n0 <- length(cases); ri <<- ri + 1; run0(...); if (ri %% 6 == 0) cases <<- cases[seq_len(n0)] }
for (r in 1:48) {
  n <- sample(60:110, 1); kx <- sample(0:2, 1); pz <- sample(3:4, 1)
  kinds <- if (r %% 3 == 0) c(0, 0, 3, -3, -4) else if (r %% 3 == 1) c(0, -3, -4, -5, 2) else c(0, 0, 2, 3)
  nl <- sapply(seq_len(pz), function(j) sample(kinds, 1))
  nl[1] <- if (r %% 2 == 0) sample(c(-3, -4), 1) else nl[1]
  run(n, kx, pz, nl, alpha = c(0.05, 0.2, 0.1)[(r %% 3) + 1], bonf = r %% 4 != 1, minsize = c(0, 10)[(r %% 2) + 1], maxdepth = c(1000, 3)[(r %% 2) + 1],
      trim = c(0.1, 0.2)[(r %% 2) + 1], vc = c(0, 0, 2, 1)[(r %% 4) + 1], mtry = if (r %% 3 == 0) 2 else 0, bties = r %% 5 < 2, seed = 3000 + r)
}
emit("partykitmobx", "partykit", list(cases))
