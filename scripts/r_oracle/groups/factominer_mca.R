# FactoMineR MCA (Indicator method, row weights, supplementary individuals, supplementary factors and supplementary quantitative variables).
#   args: blk, n, ns, j, jq, nq, ncp, rw[n], lev[j+jq], codes[(n+ns)*(j+jq)] (row-major, 1-based, active rows first), q[n*nq]
#   blocks: 0 eig, 1 pct, 2 ind coord, 3 contrib, 4 cos2, 6 var coord, 7 contrib, 8 cos2, 10 sup ind coord, 11 cos2, 12 sup category coord, 13 cos2, 14 var v.test, 15 var eta2, 16 sup category v.test, 17 sup factor eta2, 18 sup quantitative coord
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261227)
for (rep in 1:14) {
  n <- sample(14:40, 1); ns <- sample(0:3, 1); j <- sample(3:4, 1); jq <- sample(0:2, 1); nq <- sample(0:2, 1)
  tot <- n + ns; w <- j + jq
  lev <- sample(3:4, w, replace = TRUE)
  codes <- sapply(seq_len(w), function(v) { c0 <- sample(lev[v], tot, replace = TRUE); c0[1:lev[v]] <- sample(lev[v]); c0 })
  q <- matrix(rnorm(tot * nq), tot)
  rw <- if (rep %% 2 == 0) sample(1:4, n, replace = TRUE) else rep(1, n)
  df <- as.data.frame(lapply(seq_len(w), function(v) factor(paste0("v", v, "_", codes[, v]))))
  names(df) <- paste0("F", seq_len(w))
  if (nq > 0) { qq <- as.data.frame(q); names(qq) <- paste0("Q", seq_len(nq)); df <- cbind(df, qq) }
  K <- sum(lev[seq_len(j)])
  f <- MCA(df, ncp = K - j, ind.sup = if (ns > 0) (n + 1):tot else NULL, quali.sup = if (jq > 0) (j + 1):w else NULL,
           quanti.sup = if (nq > 0) (w + 1):(w + nq) else NULL, row.w = rw, graph = FALSE)
  a <- c(n, ns, j, jq, nq, K - j, rw, lev, rowmajor(codes), rowmajor(q[1:n, , drop = FALSE]))
  blocks <- list(`0` = f$eig[, 1], `1` = f$eig[, 2], `2` = f$ind$coord, `3` = f$ind$contrib, `4` = f$ind$cos2,
                 `6` = f$var$coord, `7` = f$var$contrib, `8` = f$var$cos2, `14` = f$var$v.test, `15` = f$var$eta2)
  if (ns > 0) blocks <- c(blocks, list(`10` = f$ind.sup$coord, `11` = f$ind.sup$cos2))
  if (jq > 0) blocks <- c(blocks, list(`12` = f$quali.sup$coord, `13` = f$quali.sup$cos2, `16` = f$quali.sup$v.test, `17` = f$quali.sup$eta2))
  if (nq > 0) blocks <- c(blocks, list(`18` = f$quanti.sup$coord))
  for (b in names(blocks)) add(c(as.numeric(b), a), ws(rowmajor(blocks[[b]])))
}
emit("factominer_mca", "FactoMineR", list(cases))
