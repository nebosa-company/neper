# qca_ss: QCA superSubset(). The expressions R finds are sorted conjunctions first, then by the base-3 code (one digit per condition, the first the most significant: 0 not in it, 1 negated, 2 present).
#   args: (what, index, relation 0 necessity 1 sufficiency 2 sufnec 3 necsuf, incl.cut, cov.cut, depth (0 = all), ron.cut / pri.cut, n, k, fuzzy flag per condition [k], conditions row-major [n * k], outcome [n])
#   what 0 the number of expressions, then for the expression at `index` 1 its kind (0 conjunction, 1 disjunction), 2 its code, 3 inclusion, 4 RoN (necessity) or PRI (sufficiency), 5 coverage.
suppressMessages(library(QCA))
cases <- list()
set.seed(20262802)
add <- function(args, want, rel = 1e-10) cases[[length(cases) + 1]] <<- case("ss", args, want, rel = rel, abs = if (rel == 0) 0 else 1e-12)
for (rep in 1:70) {
  n <- sample(12:30, 1); k <- sample(3:5, 1); fz <- sample(0:1, k, TRUE)
  X <- sapply(1:k, function(j) if (fz[j] == 1) round(runif(n), 3) else rbinom(n, 1, 0.55))
  if (k == 1) X <- matrix(X, ncol = 1)
  rel <- sample(0:3, 1)
  base <- if (rel %in% c(0, 3)) pmin(X[, 1], X[, 2]) else pmax(X[, 1], X[, 2])
  y <- if (rep %% 2 == 0) round(pmin(1, pmax(0, base * runif(1, 0.7, 1) + runif(n, 0, 0.25))), 3) else as.numeric(base > 0.5 | runif(n) < 0.15)
  if (var(y) == 0) next
  d <- data.frame(X); names(d) <- LETTERS[1:k]; d$OUT <- y
  ic <- if (rel >= 2) sample(c(0.5, 0.6, 0.7), 1) else sample(c(0.7, 0.8, 0.9, 1), 1); cc <- sample(c(0, 0.3, 0.5), 1); dp <- sample(c(0, 2, 3), 1); ex <- sample(c(0, 0.3, 0.5), 1)
  relname <- c("necessity", "sufficiency", "sufnec", "necsuf")[rel + 1]
  args <- list(data = d, outcome = "OUT", conditions = LETTERS[1:k], relation = relname, incl.cut = ic, cov.cut = cc, msg = FALSE)
  if (dp > 0) args$depth <- dp
  if (rel %in% c(0, 3)) args$ron.cut <- ex else args$pri.cut <- ex
  ss <- tryCatch(suppressWarnings(do.call(superSubset, args)), error = function(e) NULL)
  if (is.null(ss)) next
  ic.m <- ss$incl.cov; rn <- rownames(ic.m)
  if (anyNA(ic.m)) next
  disj <- grepl(" + ", rn, fixed = TRUE)
  code <- vapply(rn, function(s) { tk <- strsplit(s, if (grepl(" + ", s, fixed = TRUE)) " + " else "*", fixed = TRUE)[[1]]; dg <- rep(0, k); for (t in tk) { ng <- substr(t, 1, 1) == "~"; dg[match(sub("~", "", t), LETTERS)] <- if (ng) 1 else 2 }; sum(dg * 3^((k - 1):0)) }, 0)
  o <- order(as.numeric(disj), code); ic.m <- ic.m[o, , drop = FALSE]; disj <- disj[o]; code <- code[o]
  a <- function(w, i) c(w, i, rel, ic, cc, dp, ex, n, k, fz, as.vector(t(X)), y)
  add(a(0, 0), nrow(ic.m), 0)
  for (i in seq_len(nrow(ic.m))) { add(a(1, i - 1), as.numeric(disj[i]), 0); add(a(2, i - 1), code[i], 0); for (w in 1:3) add(a(w + 2, i - 1), ic.m[i, w]) }
}
emit("qca_ss", "QCA", list(cases))
