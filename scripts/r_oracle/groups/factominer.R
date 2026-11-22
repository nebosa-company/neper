# FactoMineR PCA (row and column weights, scale.unit, supplementary individuals and quantitative variables) and CA (row weights, supplementary rows and columns); axis signs are FactoMineR's own.
#   every case is the position-weighted sum of one result block; args begin (kind 0 PCA 1 CA, block index, ...)
#   PCA args: 0, blk, n, p, ncp, scale, ns, nq, rw[n], cw[p], x[n*p], xs[ns*p], q[n*nq]  (all row-major)
#     blocks: eig, pct, var coord, cor, cos2, contrib, ind coord, cos2, contrib, dist, sup ind coord, cos2, dist, sup var coord, cor, cos2
#   CA args: 1, blk, nr, nc, ncp, nrs, ncs, rw[nr], t[nr*nc], rs[nrs*nc], cs[nr*ncs]
#     blocks: eig, pct, row coord, contrib, cos2, inertia, col coord, contrib, cos2, inertia, sup row coord, cos2, sup col coord, cos2
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
emit_blocks <- function(a, blocks) for (b in seq_along(blocks)) add(c(a[1], b - 1, a[-1]), ws(blocks[[b]]))
set.seed(20261226)
for (rep in 1:24) {
  if (rep %% 2 == 0) {
    n <- sample(10:40, 1); p <- sample(3:6, 1)
    scale <- sample(c(TRUE, FALSE), 1); useW <- sample(c(TRUE, FALSE), 1)
    ns <- sample(0:3, 1); nq <- sample(0:2, 1)
    tot <- n + ns
    x <- matrix(rnorm(tot * p), tot); x[, 2] <- x[, 1] + 0.4 * x[, 2]; x <- x * rep(c(1, 3, 0.5, 2, 1, 4)[1:p], each = tot) + 2
    q <- matrix(rnorm(n * nq), n)
    rw <- if (useW) sample(1:5, n, replace = TRUE) else rep(1, n)
    cw <- if (useW) sample(1:3, p, replace = TRUE) / 2 else rep(1, p)
    df <- data.frame(x); names(df) <- paste0("V", 1:p)
    if (nq > 0) { qq <- data.frame(rbind(q, matrix(0, ns, nq))); names(qq) <- paste0("Q", 1:nq); df <- cbind(df, qq) }
    isup <- if (ns > 0) (n + 1):tot else NULL
    qsup <- if (nq > 0) (p + 1):(p + nq) else NULL
    f <- PCA(df, ind.sup = isup, quanti.sup = qsup, row.w = rw, col.w = cw, scale.unit = scale, ncp = p, graph = FALSE)
    a <- c(0, n, p, p, as.numeric(scale), ns, nq, rw, cw, rowmajor(x[1:n, ]), if (ns > 0) rowmajor(x[(n + 1):tot, ]), rowmajor(q))
    blocks <- list(f$eig[, 1], f$eig[, 2], f$var$coord, f$var$cor, f$var$cos2, f$var$contrib, f$ind$coord, f$ind$cos2, f$ind$contrib, f$ind$dist)
    if (ns > 0) blocks <- c(blocks, list(f$ind.sup$coord, f$ind.sup$cos2, f$ind.sup$dist))
    if (nq > 0) blocks <- c(blocks, list(f$quanti.sup$coord, f$quanti.sup$cor, f$quanti.sup$cos2))
    ids <- c(0:9, if (ns > 0) 10:12, if (nq > 0) 13:15)
    for (i in seq_along(blocks)) add(c(a[1], ids[i], a[-1]), ws(rowmajor(blocks[[i]])))
  } else {
    r <- sample(4:9, 1); cc <- sample(3:7, 1); nrs <- sample(0:2, 1); ncs <- sample(0:2, 1)
    useW <- sample(c(TRUE, FALSE), 1)
    full <- matrix(rpois((r + nrs) * (cc + ncs), 6) + 1, r + nrs)
    rw <- if (useW) sample(1:3, r, replace = TRUE) else rep(1, r)
    tb <- full[1:r, 1:cc]
    df <- data.frame(full)
    rsup <- if (nrs > 0) (r + 1):(r + nrs) else NULL
    csup <- if (ncs > 0) (cc + 1):(cc + ncs) else NULL
    nd <- min(r - 1, cc - 1)
    f <- CA(df, row.sup = rsup, col.sup = csup, row.w = rw, ncp = nd, graph = FALSE)
    a <- c(1, r, cc, nd, nrs, ncs, rw, rowmajor(tb), if (nrs > 0) rowmajor(full[(r + 1):(r + nrs), 1:cc]), if (ncs > 0) rowmajor(full[1:r, (cc + 1):(cc + ncs)]))
    blocks <- list(f$eig[, 1], f$eig[, 2], f$row$coord, f$row$contrib, f$row$cos2, f$row$inertia, f$col$coord, f$col$contrib, f$col$cos2, f$col$inertia)
    ids <- 0:9
    if (nrs > 0) { blocks <- c(blocks, list(f$row.sup$coord, f$row.sup$cos2)); ids <- c(ids, 10:11) }
    if (ncs > 0) { blocks <- c(blocks, list(f$col.sup$coord, f$col.sup$cos2)); ids <- c(ids, 12:13) }
    for (i in seq_along(blocks)) add(c(a[1], ids[i], a[-1]), ws(rowmajor(blocks[[i]])))
  }
}
emit("factominer", "FactoMineR", list(cases))
