# actuar, third group: hierarchical credibility (cm with two and three levels, Buhlmann-Gisler, Ohlsson and iterative) and regression credibility with the barycenter intercept. Layouts at each block.
suppressMessages(library(actuar))
cases <- list()
set.seed(20267002)
# cm() hierarchical (nl levels below the portfolio, rows are the entities): "hier" args (nl, nr, nt, meth 0 Buhlmann-Gisler 1 Ohlsson 2 iterative, parlen[nl], par[] (0-based, concatenated), nn[nl], ratios[nr*nt] row-major, weights[nr*nt] (NaN missing), idx)
# the idx-th number of c(unbiased or iterative, unlist(cred), unlist(means))
for (rep in 1:12) {
  nl <- if (rep %% 4 == 3) 3 else 2; meth <- (rep %/% 2) %% 3
  ns <- sample(2:3, 1)
  if (nl == 2) { upn <- sample(2:4, ns, replace = TRUE); sector <- rep(seq_len(ns), upn); unit <- seq_along(sector); df <- data.frame(sector = sector, unit = unit) }
  else {
    ucount <- sample(2:3, ns, replace = TRUE); usector <- rep(seq_len(ns), ucount); ccount <- sample(2:3, length(usector), replace = TRUE)
    sector <- rep(usector, ccount); unit <- rep(seq_along(usector), ccount); df <- data.frame(sector = sector, unit = unit, contract = seq_along(sector))
  }
  nr <- nrow(df); nt <- sample(4:7, 1)
  R <- matrix(round(rnorm(nr * nt, rep(rnorm(nr, 10, 2), nt), 3), 3), nr, nt); W <- matrix(round(runif(nr * nt, 0.5, 5), 3), nr, nt)
  if (rep %% 2 == 0) { na <- sample(nr * nt, 3); for (k in na) { rr0 <- (k - 1) %% nr + 1; cc <- (k - 1) %/% nr + 1; if (sum(!is.na(W[rr0, ])) > 1) { W[rr0, cc] <- NA; R[rr0, cc] <- NA } } }
  colnames(R) <- paste0("r", seq_len(nt)); colnames(W) <- paste0("w", seq_len(nt)); d <- cbind(df, R, W)
  fm <- if (nl == 2) ~sector + sector:unit else ~sector + sector:unit + sector:unit:contract
  fit <- tryCatch(suppressWarnings(cm(fm, data = d, ratios = paste0("r", seq_len(nt)), weights = paste0("w", seq_len(nt)), method = c("Buhlmann-Gisler", "Ohlsson", "iterative")[meth + 1])), error = function(e) NULL)
  if (is.null(fit)) next
  ord <- fit$ordering; nn <- sapply(fit$means[1:nl], length)
  want <- c(if (meth == 2) fit$iterative else fit$unbiased, unlist(fit$cred), unlist(fit$means))
  for (i in seq_along(want)) if (is.finite(want[i])) cases[[length(cases) + 1]] <- case("hier", c(nl, nr, nt, meth, sapply(ord, length), unlist(ord) - 1, nn, as.vector(t(R)), as.vector(t(W)), i - 1), want[i], rel = 1e-10, abs = 1e-12)
}
# cm() with regformula and adj.intercept = TRUE (hache.barycenter): "hb" args (n, t, p, meth 0 unbiased 1 iterative, ratios[n t], weights[n t] (NaN missing), xreg[t p], idx)
# the idx-th number of c(diag(A), s2, coll, then per contract ind, diag(cred), coefficients)
for (rep in 1:8) {
  n <- sample(4:10, 1); tt <- sample(6:12, 1); p <- sample(2:3, 1); meth <- rep %% 2
  xr <- cbind(1, 1:tt, if (p == 3) (1:tt)^2 / 10 else NULL)[, seq_len(p), drop = FALSE]
  bi <- cbind(rnorm(n, 50, 8), rnorm(n, 1.5, 1), if (p == 3) rnorm(n, 0.2, 0.3) else NULL)[, seq_len(p), drop = FALSE]
  ratios <- t(sapply(seq_len(n), function(i) as.vector(xr %*% bi[i, ]) + rnorm(tt, 0, 3)))
  weights <- matrix(round(runif(n * tt, 50, 300)), n)
  if (rep %% 3 == 0) for (k in sample(n * tt, 4)) { i <- (k - 1) %% n + 1; if (sum(!is.na(weights[i, ])) > p + 2) { weights[i, (k - 1) %/% n + 1] <- NA; ratios[i, (k - 1) %/% n + 1] <- NA } }
  if (rep %in% c(5, 8)) { weights[2, ] <- NA; ratios[2, ] <- NA }  # a contract with no data at all
  r <- tryCatch(suppressWarnings(actuar:::hache.barycenter(ratios, weights, xr, c("unbiased", "iterative")[meth + 1], sqrt(.Machine$double.eps), 100, FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  ab <- if (meth == 0) r$unbiased else r$iterative
  v <- c(diag(ab[[1]]), ab[[2]], r$means[[1]])
  for (cc in seq_len(n)) v <- c(v, r$means[[2]][, cc], diag(r$cred[, , cc]), r$adj.models[[cc]]$coefficients)
  for (w in seq_along(v)) cases[[length(cases) + 1]] <- case("hb", c(n, tt, p, meth, as.vector(t(ratios)), as.vector(t(weights)), as.vector(t(xr)), w - 1), v[w], rel = 1e-9, abs = 1e-10)
}
emit("actuar3", "actuar", list(cases))
