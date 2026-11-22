# FactoMineR dimdesc (condes) of the principal axes of a weighted PCA, proba = 1 so every row is kept; results are compared in input order.
#   args: blk, n, nq, jf, rw[n], lev[jf], y[n], xq[n*nq], codes[n*jf] (row-major, 1-based)
#   blocks: 0 correlation, 1 its p.value, 2 R2 of each factor, 3 its p.value, 4 category Estimate, 5 category p.value
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-12)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261229)
for (rep in 1:12) {
  n <- sample(15:40, 1); p <- sample(3:5, 1); jf <- sample(1:3, 1)
  lev <- sample(3:4, jf, replace = TRUE)
  codes <- sapply(seq_len(jf), function(v) { c0 <- sample(lev[v], n, replace = TRUE); c0[1:lev[v]] <- sample(lev[v]); c0 })
  codes <- matrix(codes, n)
  x <- matrix(rnorm(n * (p + 1)), n); x[, 2] <- x[, 1] + 0.5 * x[, 2]
  rw <- if (rep %% 2 == 0) sample(1:4, n, replace = TRUE) else rep(1, n)
  df <- as.data.frame(x); names(df) <- paste0("Q", seq_len(p + 1))
  for (v in seq_len(jf)) df[[paste0("F", v)]] <- factor(paste0("v", v, "_", codes[, v]))
  f <- PCA(df, quanti.sup = p + 1, quali.sup = (p + 2):(p + 1 + jf), row.w = rw, ncp = 3, graph = FALSE)
  d <- dimdesc(f, axes = 1:3, proba = 1)
  catnames <- unlist(lapply(seq_len(jf), function(v) paste0("F", v, "=v", v, "_", seq_len(lev[v]))))
  for (k in 1:3) {
    y <- f$ind$coord[, k]
    a <- c(n, p + 1, jf, rw, lev, y, rowmajor(x), rowmajor(codes))
    q <- d[[k]]$quanti[names(df)[1:(p + 1)], ]
    fq <- d[[k]]$quali; if (is.null(dim(fq))) fq <- matrix(fq, 1, dimnames = list("F1", NULL)); fq <- fq[paste0("F", seq_len(jf)), , drop = FALSE]
    ct <- d[[k]]$category[catnames, ]
    add(c(0, a), ws(q[, 1])); add(c(1, a), ws(q[, 2]))
    add(c(2, a), ws(fq[, 1])); add(c(3, a), ws(fq[, 2]))
    add(c(4, a), ws(ct[, 1])); add(c(5, a), ws(ct[, 2]))
  }
}
emit("factominer_dimdesc", "FactoMineR", list(cases))
