# partykit lmtree with case weights, an offset, clusters and the vcov settings opg, info and sandwich.
#   args: (sel, n, kx, pz, alpha, bonf, minsize, maxdepth, trim, vc, usew, useoff, usecl, nl[pz], w[n], off[n], cl[n], xr[n*kx], z[n*pz], y[n])
#   vc 0 opg, 1 info, 2 sandwich; usew/useoff/usecl 1 when the weights, offset, cluster are passed (w positive integers, cl codes 0..C-1);
#   nl[j] 0 numeric partitioning variable, L unordered factor with codes 0..L-1
#   sel 1 node count, 2 sum id*zvar, 3 sum id*split, 4 sum id*nobs, 5 sum id*p.value over inner nodes, 6 sum id*sum_j j*coef_j, 7 sum id*objfun, 9 sum row*node id,
#       10 sum id*sum of the instability statistics, 11 sum id*sum of the adjusted p values (NA as 0), 14 sum row*node id of as.constparty(t)$fitted plus the sum of its stored response
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261261)
run <- function(n, kx, pz, nl, alpha, bonf, minsize, maxdepth, trim, vc, usew, useoff, usecl, ncl = 4, noise = 1.5) {
  Z <- lapply(seq_len(pz), function(j) if (nl[j] == 0) round(rnorm(n) * 5, if (j == 1) 0 else 1) else sample(0:(nl[j] - 1), n, TRUE))
  X <- lapply(seq_len(kx), function(j) round(rnorm(n) * 3, 1))
  g1 <- if (nl[1] == 0) as.numeric(Z[[1]] > median(Z[[1]])) else as.numeric(Z[[1]] %% 2)
  g2 <- if (pz >= 2) (if (nl[2] == 0) as.numeric(Z[[2]] > median(Z[[2]])) else as.numeric(Z[[2]] %% 2)) else 0
  eta <- 1 + 3 * g1 + 2 * g2
  for (j in seq_len(kx)) eta <- eta + (1 + 2 * g1 * (j == 1)) * X[[j]]
  w <- if (usew) sample(1:3, n, TRUE) else rep(1, n)
  off <- if (useoff) round(rnorm(n), 2) else rep(0, n)
  cl <- if (usecl) sample(0:(ncl - 1), n, TRUE) else rep(0, n)
  y <- round(eta + off + rnorm(n) * noise, 2)
  df <- data.frame(y = y)
  for (j in seq_len(kx)) df[[paste0("x", j)]] <- X[[j]]
  for (j in seq_len(pz)) df[[paste0("z", j)]] <- if (nl[j] == 0) Z[[j]] else factor(Z[[j]], levels = 0:(nl[j] - 1))
  df$w <- w; df$off <- off; df$cl <- factor(cl)
  fml <- as.formula(paste("y ~", if (kx > 0) paste0("x", seq_len(kx), collapse = " + ") else "1", "|", paste0("z", seq_len(pz), collapse = " + ")))
  mc <- list(alpha = alpha, bonferroni = bonf, maxdepth = if (maxdepth >= 1000) Inf else maxdepth, trim = trim, vcov = c("opg", "info", "sandwich")[vc + 1])
  if (minsize > 0) mc$minsize <- minsize
  args <- list(formula = fml, data = df, fit = partykit:::lmfit, control = do.call(mob_control, mc))
  if (usew) args$weights <- quote(w)
  if (useoff) args$offset <- quote(off)
  if (usecl) args$cluster <- quote(cl)
  t <- do.call(mob, args)
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
  a0 <- c(n, kx, pz, alpha, bonf, minsize, maxdepth, trim, vc, as.numeric(usew), as.numeric(useoff), as.numeric(usecl), nl, w, off, cl, unlist(X), unlist(Z), y)
  add("lo", c(1, a0), length(ids)); add("lo", c(2, a0), sum(ids * vid)); add("lo", c(3, a0), sum(ids * brk))
  add("lo", c(4, a0), sum(ids * nob)); add("lo", c(5, a0), sum(ids * pv)); add("lo", c(6, a0), sum(ids * cs))
  add("lo", c(7, a0), sum(ids * of)); add("lo", c(9, a0), sum(seq_len(n) * pn))
  add("lo", c(10, a0), sum(ids * st)); add("lo", c(11, a0), sum(ids * ap))
  # the party conversions of the tree keep its splits and node ids
  cp <- as.constparty(t)
  add("lo", c(14, a0), sum(seq_len(n) * cp$fitted[["(fitted)"]]) + sum(cp$fitted[["(response)"]]))
}
rep_i <- 0
for (usew in c(FALSE, TRUE)) for (useoff in c(FALSE, TRUE)) for (usecl in c(FALSE, TRUE)) for (vc in 0:2) {
  if (!usew && !useoff && !usecl && vc == 0) next
  for (r in 1:2) {
    rep_i <- rep_i + 1
    n <- sample(45:65, 1); kx <- sample(0:2, 1); pz <- sample(2:3, 1)
    nl <- sapply(seq_len(pz), function(j) if (rep_i %% 3 == 0) sample(c(0, 3, 4), 1) else sample(c(0, 0, 2, 3), 1))
    run(n, kx, pz, nl, alpha = c(0.05, 0.2, 0.05)[(rep_i %% 3) + 1], bonf = rep_i %% 3 != 1, minsize = c(0, 10)[(rep_i %% 2) + 1],
        maxdepth = c(1000, 3)[(rep_i %% 2) + 1], trim = c(0.1, 0.2)[(rep_i %% 2) + 1], vc = vc, usew = usew, useoff = useoff, usecl = usecl)
  }
}
emit("partykitmobopt", "partykit", list(cases))
