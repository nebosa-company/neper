# partykit lmtree and glmtree (MOB): structure, split points, coefficients, instability tests and predictions of linear-model trees.
#   args: (sel, n, kx, pz, fam, alpha, bonf, minsize, maxdepth, trim, prune, center, nl[pz], xr[n*kx], z[n*pz], y[n])
#   prune 0 none, 1 AIC, 2 BIC; center 1 = numsplit "center"; fam 0 gaussian lmtree, 1 binomial, 2 poisson glmtree; nl[j] 0 numeric partitioning variable, L unordered factor with codes 0..L-1; minsize 0 = default; maxdepth 1000 = Inf
#   sel 1 node count, 2 sum id*zvar, 3 sum id*split (numeric break, or sum (level+1)*child for a factor), 4 sum id*nobs,
#       5 sum id*p.value over inner nodes, 6 sum id*sum_j j*coef_j, 7 sum id*objfun, 8 sum fitted values, 9 sum row*node id,
#       10 sum id*sum of the instability statistics, 11 sum id*sum of the adjusted p values (NA as 0),
#       12 sum row*node id and 13 sum fitted on newdata (every numeric column * 1.1 + 0.05, numeric z only)
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261222)
run <- function(n, kx, pz, fam, nl, alpha, bonf, minsize, maxdepth, trim, dec, prune = 0, center = 0, noise = 1.5) {
  Z <- lapply(seq_len(pz), function(j) if (nl[j] == 0) round(rnorm(n) * 5, dec) else sample(0:(nl[j] - 1), n, TRUE))
  X <- lapply(seq_len(kx), function(j) round(rnorm(n) * 3, 1))
  # slope and intercept shifts driven by the first one or two partitioning variables
  g1 <- if (nl[1] == 0) as.numeric(Z[[1]] > median(Z[[1]])) else as.numeric(Z[[1]] %% 2)
  g2 <- if (pz >= 2) (if (nl[2] == 0) as.numeric(Z[[2]] > median(Z[[2]])) else as.numeric(Z[[2]] %% 2)) else 0
  eta <- 1 + 3 * g1 + 2 * g2
  for (j in seq_len(kx)) eta <- eta + (1 + 2 * g1 * (j == 1)) * X[[j]]
  y <- if (fam == 0) round(eta + rnorm(n) * noise, 2) else if (fam == 1) as.numeric(runif(n) < plogis(0.35 * (eta - mean(eta)))) else as.numeric(rpois(n, exp(0.15 * (eta - mean(eta)) + 0.5)))
  df <- data.frame(y = y)
  for (j in seq_len(kx)) df[[paste0("x", j)]] <- X[[j]]
  for (j in seq_len(pz)) df[[paste0("z", j)]] <- if (nl[j] == 0) Z[[j]] else factor(Z[[j]], levels = 0:(nl[j] - 1))
  fml <- as.formula(paste("y ~", if (kx > 0) paste0("x", seq_len(kx), collapse = " + ") else "1", "|", paste0("z", seq_len(pz), collapse = " + ")))
  args <- list(formula = fml, data = df, alpha = alpha, bonferroni = bonf, maxdepth = if (maxdepth >= 1000) Inf else maxdepth, trim = trim)
  if (minsize > 0) args$minsize <- minsize
  if (prune > 0) args$prune <- c("AIC", "BIC")[prune]
  if (center > 0) args$numsplit <- "center"
  if (fam > 0) args$family <- if (fam == 1) binomial() else poisson()
  t <- do.call(if (fam == 0) lmtree else glmtree, args)
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
  a0 <- c(n, kx, pz, fam, alpha, bonf, minsize, maxdepth, trim, prune, center, nl, unlist(X), unlist(Z), y)
  add("lm", c(1, a0), length(ids)); add("lm", c(2, a0), sum(ids * vid)); add("lm", c(3, a0), sum(ids * brk))
  add("lm", c(4, a0), sum(ids * nob)); add("lm", c(5, a0), sum(ids * pv)); add("lm", c(6, a0), sum(ids * cs))
  add("lm", c(7, a0), sum(ids * of)); add("lm", c(8, a0), sum(predict(t, newdata = df)))
  add("lm", c(9, a0), sum(seq_len(n) * pn)); add("lm", c(10, a0), sum(ids * st)); add("lm", c(11, a0), sum(ids * ap))
  if (all(nl == 0)) {
    nd2 <- df; for (j in 2:ncol(nd2)) nd2[[j]] <- nd2[[j]] * 1.1 + 0.05
    add("lm", c(12, a0), sum(seq_len(n) * predict(t, newdata = nd2, type = "node")))
    add("lm", c(13, a0), sum(predict(t, newdata = nd2)))
  }
}
for (rep in 1:28) {
  fam <- if (rep <= 20) 0 else (rep %% 2) + 1
  n <- sample(if (fam == 0) 50:100 else 100:170, 1); kx <- sample(0:2, 1); pz <- sample(2:4, 1)
  nl <- sapply(seq_len(pz), function(j) if (rep %% 3 == 0) sample(c(0, 3, 4), 1) else sample(c(0, 0, 2, 3), 1))
  if (rep %% 4 == 1) nl[] <- 0
  run(n, kx, pz, fam, nl, alpha = c(0.05, 0.2, 0.05, 0.5)[(rep %% 4) + 1], bonf = rep %% 3 != 1,
      minsize = c(0, 10, 0, 15)[((rep + 1) %% 4) + 1], maxdepth = c(1000, 1000, 2, 3)[(rep %% 4) + 1],
      trim = c(0.1, 0.1, 0.2, 0.1)[(rep %% 4) + 1], dec = if (rep %% 5 == 0) 1 else 0, prune = if (rep %% 4 == 1) 0 else (rep %% 2) + 1, center = as.numeric(rep %% 3 == 2))
}
for (rep in 37:42) {
  fam <- if (rep <= 40) 0 else 1; n <- sample(120:180, 1); pz <- 3; nl <- c(0, 0, 0)
  run(n, 1, pz, fam, nl, alpha = 0.9, bonf = FALSE, minsize = 12, maxdepth = 4, trim = 0.1, dec = 0, prune = (rep %% 2) + 1, center = 0, noise = 9)
}
emit("partykitmob", "partykit", list(cases))
