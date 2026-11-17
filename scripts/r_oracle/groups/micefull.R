# mice over numeric and factor columns after set.seed: polyreg, polr, cart, logreg with factor predictors, passive imputation, partial and permuted visit sequences, post-processing.
# One case per data set; args: (n, p, m, maxit, seed, data[n*p] column-major with NaN for missing and factor codes 1..L, ncat[p], meth[p], pred[p*p] row-major (row = target), nv, visit[nv] 0-based, post[2p] lower/upper (NaN none), pas[3p] kind/a/b per column);
# the answer is sum_i (i + 1) v_i over the imputed values (factor codes for factors) in the order of the columns with imputations, imputation by imputation, rows in order
suppressMessages(library(mice))
cases <- list()
set.seed(20261118)
CODE <- c(norm.nob = 0, norm = 1, norm.predict = 2, pmm = 3, logreg = 4, norm.boot = 5, logreg.boot = 6, mean = 7, sample = 8, cart = 10, polyreg = 11, polr = 12)
add_case <- function(df, meth, pm, vs = NULL, post = NULL, pas = NULL, m = sample(1:3, 1), maxit = sample(1:3, 1), tol = c(1e-6, 1e-8)) {
  n <- nrow(df); p <- ncol(df); seed <- sample(1:100000, 1)
  pmeth <- meth; names(pmeth) <- names(df)
  pst <- rep("", p); names(pst) <- names(df)
  if (!is.null(post)) for (j in seq_len(p)) if (!is.na(post[2 * j - 1]) || !is.na(post[2 * j]))
    pst[j] <- sprintf("imp[[j]][, i] <- squeeze(imp[[j]][, i], c(%.17g, %.17g))", ifelse(is.na(post[2 * j - 1]), -Inf, post[2 * j - 1]), ifelse(is.na(post[2 * j]), Inf, post[2 * j]))
  pmx <- pm; dimnames(pmx) <- list(names(df), names(df))
  args <- list(df, m = m, maxit = maxit, method = pmeth, predictorMatrix = pmx, post = pst, seed = seed, printFlag = FALSE)
  if (!is.null(vs)) args$visitSequence <- vs
  imp <- tryCatch(suppressWarnings(do.call(mice, args)), error = function(e) NULL)
  if (is.null(imp) || !is.null(imp$loggedEvents)) return(invisible(NULL))
  vseq <- match(imp$visitSequence, names(df))
  flat <- c()
  for (j in seq_len(p)) if (j %in% vseq && meth[j] != "" && nrow(imp$imp[[j]]) > 0) {
    for (im in seq_len(m)) {
      v <- imp$imp[[j]][[im]]
      if (is.factor(df[[j]])) v <- as.integer(factor(as.character(v), levels = levels(df[[j]])))
      flat <- c(flat, as.numeric(v))
    }
  }
  if (length(flat) == 0 || anyNA(flat)) return(invisible(NULL))
  dat <- sapply(df, as.numeric); dat[is.na(dat)] <- NaN
  ncat <- sapply(df, function(x) if (is.factor(x)) nlevels(x) else 0)
  mc <- ifelse(meth == "", -1, ifelse(substr(meth, 1, 1) == "~", 20, CODE[meth]))
  if (is.null(post)) post <- rep(NA, 2 * p); if (is.null(pas)) pas <- rep(0, 3 * p)
  cases[[length(cases) + 1]] <<- case("mice_full", c(n, p, m, maxit, seed, as.vector(dat), ncat, mc, as.vector(t(pm)), length(vseq), vseq - 1, post, pas), sum(seq_along(flat) * flat), rel = tol[1], abs = tol[2])
}
mkfac <- function(score, k, ordered = FALSE) {
  f <- cut(score, breaks = quantile(score, seq(0, 1, length.out = k + 1)), include.lowest = TRUE, labels = letters[1:k])
  if (ordered) factor(f, ordered = TRUE) else f
}
hole <- function(x, cnt) { x[sample(length(x), cnt)] <- NA; x }
base <- function(n) { z <- rnorm(n); list(a = round(z + rnorm(n, 0, 0.6), 3), b = round(0.5 * z + rnorm(n), 3), z = z) }
fullpm <- function(p, zero = integer()) { pm <- matrix(1, p, p); diag(pm) <- 0; pm[, zero] <- 0; diag(pm) <- 0; pm }

# polyreg: a factor target (3 or 4 levels), numeric predictors and a factor predictor
for (rep in 1:40) {
  n <- sample(45:90, 1); b <- base(n); k <- sample(3:4, 1)
  F <- hole(mkfac(b$z + rnorm(n, 0, 0.8), k), sample(6:12, 1)); G <- mkfac(b$b + rnorm(n), sample(2:3, 1))
  df <- data.frame(F = F, A = hole(b$a, sample(4:8, 1)), B = b$b, G = G)
  if (rep %% 4 == 0) df$G <- NULL
  meth <- c("polyreg", sample(c("norm.nob", "pmm", "norm"), 1), "", if (ncol(df) == 4) "" else NULL)
  add_case(df, meth, fullpm(ncol(df)))
}
# polr: an ordered factor target
for (rep in 1:40) {
  n <- sample(45:90, 1); b <- base(n); k <- sample(3:4, 1)
  O <- hole(mkfac(b$z + rnorm(n, 0, 0.8), k, TRUE), sample(6:12, 1)); G <- mkfac(b$b + rnorm(n), sample(2:3, 1))
  df <- data.frame(O = O, A = hole(b$a, sample(4:8, 1)), B = b$b, G = G)
  if (rep %% 4 == 0) df$G <- NULL
  meth <- c("polr", sample(c("norm.nob", "pmm"), 1), "", if (ncol(df) == 4) "" else NULL)
  add_case(df, meth, fullpm(ncol(df), zero = 1))
}
# cart: numeric and factor targets
for (rep in 1:40) {
  n <- sample(45:90, 1); b <- base(n); k <- sample(2:4, 1)
  F <- hole(mkfac(b$z + rnorm(n, 0, 0.8), k), sample(6:12, 1)); G <- mkfac(b$b + rnorm(n), sample(2:3, 1))
  df <- data.frame(A = hole(b$a, sample(5:12, 1)), F = F, B = b$b, G = G)
  if (rep %% 3 == 0) df$G <- NULL
  meth <- c(sample(c("cart", "cart", "pmm"), 1), "cart", "", if (ncol(df) == 4) "" else NULL)
  add_case(df, meth, fullpm(ncol(df)))
}
# logreg with a factor predictor and pmm / norm.boot / mean / sample companions
for (rep in 1:30) {
  n <- sample(50:90, 1); b <- base(n)
  Bn <- hole(mkfac(b$z + rnorm(n, 0, 0.8), 2), sample(6:12, 1)); G <- mkfac(b$b + rnorm(n), 3)
  df <- data.frame(Bn = Bn, A = hole(b$a, sample(5:9, 1)), B = b$b, G = G)
  meth <- c(sample(c("logreg", "logreg.boot"), 1), sample(c("pmm", "norm.boot", "mean", "sample", "norm.predict"), 1), "", "")
  add_case(df, meth, fullpm(4))
}
# passive imputation: a column that is a function of two imputed columns
for (rep in 1:40) {
  n <- sample(40:80, 1); b <- base(n); kind <- (rep - 1) %% 5
  a <- b$a; bb <- b$b + 3
  s <- switch(kind + 1, a + bb, a * bb, a - bb, a / bb, a^2)
  ma <- sample(n, sample(4:8, 1)); mb <- sample(n, sample(4:8, 1))
  A <- a; A[ma] <- NA; Bv <- bb; Bv[mb] <- NA; S <- s; S[union(ma, mb)] <- NA
  if (kind == 4) S <- s; if (kind == 4) S[ma] <- NA
  Cc <- round(b$z + rnorm(n, 0, 0.5), 3)
  df <- data.frame(A = round(A, 3), B = round(Bv, 3), S = round(S, 4), C = Cc)
  pass <- switch(kind + 1, "~I(A + B)", "~I(A * B)", "~I(A - B)", "~I(A / B)", "~I(A^2)")
  meth <- c(sample(c("norm.nob", "pmm", "norm"), 1), sample(c("norm.nob", "pmm"), 1), pass, "")
  pm <- fullpm(4, zero = if (kind %in% c(0, 2)) 3 else integer())
  pas <- rep(0, 12); pas[7:9] <- c(kind, 0, if (kind == 4) 0 else 1)
  add_case(df, meth, pm, pas = pas)
}
# visit sequences (permutations, partial) and post-processing bounds on numeric data
for (rep in 1:50) {
  n <- sample(40:80, 1); b <- base(n); p <- 4
  X <- data.frame(V1 = hole(b$a, 6), V2 = hole(round(b$a + b$b, 3), 7), V3 = hole(b$b, 5), V4 = round(rnorm(n), 3))
  meth <- c(sample(c("norm.nob", "pmm", "norm"), 3, replace = TRUE), "")
  nv <- sample(1:3, 1); vs <- sample(1:3, nv)
  partial <- rep %% 2 == 0
  if (partial) { meth[setdiff(1:3, vs)] <- meth[setdiff(1:3, vs)] } else vs <- sample(1:3)
  post <- rep(NA, 8); if (rep %% 3 == 0) post[1:2] <- c(quantile(X$V1, 0.1, na.rm = TRUE), quantile(X$V1, 0.9, na.rm = TRUE))
  add_case(X, meth, fullpm(4), vs = names(X)[vs], post = post)
}
emit("micefull", c("mice"), list(cases))
