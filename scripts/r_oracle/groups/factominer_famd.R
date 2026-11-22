# FactoMineR FAMD (active quantitative and qualitative variables, row weights, supplementary individuals).
#   args: blk, n, ns, pq, jf, ncp, rw[n], lev[jf], x[(n+ns)*pq], codes[(n+ns)*jf] (row-major, 1-based, active rows first)
#   blocks: 0 eig, 1 pct, 6 ind coord, 7 cos2, 8 contrib, 9 dist, 10 sup ind coord, 11 cos2, 12 dist, 13 quali.var coord, 14 cos2, 15 v.test,
#           16 var coord, 17 contrib, 18 cos2, 20 quanti.var coord, 21 cos2, 22 contrib, 23 quali.var contrib
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261228)
for (rep in 1:14) {
  n <- sample(15:40, 1); ns <- sample(0:3, 1); pq <- sample(2:4, 1); jf <- sample(2:3, 1)
  tot <- n + ns
  lev <- sample(3:4, jf, replace = TRUE)
  codes <- sapply(seq_len(jf), function(v) { c0 <- sample(lev[v], tot, replace = TRUE); c0[1:lev[v]] <- sample(lev[v]); c0 })
  x <- matrix(rnorm(tot * pq), tot) * rep(c(1, 3, 0.5, 2)[1:pq], each = tot) + 2
  rw <- if (rep %% 2 == 0) sample(1:4, n, replace = TRUE) else rep(1, n)
  df <- as.data.frame(x); names(df) <- paste0("Q", seq_len(pq))
  for (v in seq_len(jf)) df[[paste0("F", v)]] <- factor(paste0("v", v, "_", codes[, v]))
  K <- sum(lev)
  ncp <- pq + K - jf
  f <- FAMD(df, ncp = ncp, ind.sup = if (ns > 0) (n + 1):tot else NULL, row.w = rw, graph = FALSE)
  a <- c(n, ns, pq, jf, ncp, rw, lev, rowmajor(x), rowmajor(codes))
  blocks <- list(`0` = f$eig[, 1], `1` = f$eig[, 2], `6` = f$ind$coord, `7` = f$ind$cos2, `8` = f$ind$contrib, `9` = f$ind$dist,
                 `13` = f$quali.var$coord, `14` = f$quali.var$cos2, `15` = f$quali.var$v.test,
                 `16` = f$var$coord, `17` = f$var$contrib, `18` = f$var$cos2,
                 `20` = f$quanti.var$coord, `21` = f$quanti.var$cos2, `22` = f$quanti.var$contrib, `23` = f$quali.var$contrib)
  if (ns > 0) blocks[["14"]] <- NULL  # FactoMineR indexes the active-row weights with a full-length logical when ind.sup is given: its cos2 is NaN
  if (ns > 0) blocks <- c(blocks, list(`10` = f$ind.sup$coord, `11` = f$ind.sup$cos2, `12` = f$ind.sup$dist))
  for (b in names(blocks)) add(c(as.numeric(b), a), ws(rowmajor(blocks[[b]])))
}
emit("factominer_famd", "FactoMineR", list(cases))
