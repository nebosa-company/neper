# FactoMineR MFA over quantitative groups (standardised "s" and centred "c"), row weights, supplementary individuals.
#   args: blk, n, ns, P, ng, ncp, rw[n], gsz[ng], gty[ng] (1 = "s", 0 = "c"), x[n*P], xs[ns*P] (row-major)
#   blocks: 0 eig, 1 pct, 2 var coord, 3 cor, 4 cos2, 5 contrib (global PCA over the weighted columns), 6 ind coord, 7 cos2, 8 contrib, 9 dist,
#           10 sup coord, 11 cos2, 12 dist, 13 Lg, 14 RV, 15 group coord, 16 contrib, 17 cos2, 18 dist2, 19 group-factor correlation
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261230)
for (rep in 1:12) {
  n <- sample(12:35, 1); ns <- sample(0:3, 1); ng <- sample(2:3, 1)
  gsz <- sample(2:3, ng, replace = TRUE); gty <- sample(0:1, ng, replace = TRUE)
  P <- sum(gsz); tot <- n + ns
  x <- matrix(rnorm(tot * P), tot) * rep(c(1, 3, 0.5, 2, 1, 4, 2, 1, 3)[1:P], each = tot) + 1
  x[, 2] <- x[, 1] + 0.5 * x[, 2]
  rw <- if (rep %% 2 == 0) sample(1:4, n, replace = TRUE) else rep(1, n)
  df <- as.data.frame(x); names(df) <- paste0("V", seq_len(P))
  f <- MFA(df, group = gsz, type = ifelse(gty == 1, "s", "c"), ind.sup = if (ns > 0) (n + 1):tot else NULL, ncp = 5, row.w = rw, graph = FALSE)
  g <- f$global.pca
  a <- c(n, ns, P, ng, 5, rw, gsz, gty, rowmajor(x[1:n, ]), if (ns > 0) rowmajor(x[(n + 1):tot, ]))
  blocks <- list(`0` = g$eig[, 1], `1` = g$eig[, 2], `2` = g$var$coord, `3` = g$var$cor, `4` = g$var$cos2, `5` = g$var$contrib,
                 `6` = g$ind$coord, `7` = g$ind$cos2, `8` = g$ind$contrib, `9` = g$ind$dist,
                 `13` = f$group$Lg, `14` = f$group$RV, `15` = f$group$coord, `16` = f$group$contrib, `17` = f$group$cos2,
                 `18` = f$group$dist2, `19` = f$group$correlation)
  if (ns > 0) blocks <- c(blocks, list(`10` = g$ind.sup$coord, `11` = g$ind.sup$cos2, `12` = g$ind.sup$dist))
  for (b in names(blocks)) add(c(as.numeric(b), a), ws(rowmajor(blocks[[b]])))
}
emit("factominer_mfa", "FactoMineR", list(cases))
