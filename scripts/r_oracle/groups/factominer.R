# FactoMineR PCA (scale.unit = TRUE) and CA; axis signs are free so vectors are compared as absolute values.
#   args: (kind 0 PCA 1 CA, r, c, data[r*c] row-major)
#   PCA fn: "eig" "vcoord" "vcontrib" "icoord" "icos2" "icontrib" "idist"; CA fn: "ceig" "rcoord" "rcontrib" "ccoord" "ccos2"
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261226)
for (rep in 1:20) {
  if (rep %% 2 == 0) {
    n <- sample(8:40, 1); p <- sample(3:6, 1); x <- matrix(rnorm(n * p), n); x[, 2] <- x[, 1] + 0.4 * x[, 2]
    f <- PCA(x, graph = FALSE, ncp = p, scale.unit = TRUE); a <- c(0, n, p, rowmajor(x))
    add("eig", a, ws(f$eig[, 1])); add("vcoord", a, ws(abs(rowmajor(f$var$coord)))); add("vcontrib", a, ws(rowmajor(f$var$contrib)))
    add("icoord", a, ws(abs(rowmajor(f$ind$coord)))); add("icos2", a, ws(rowmajor(f$ind$cos2))); add("icontrib", a, ws(rowmajor(f$ind$contrib))); add("idist", a, ws(f$ind$dist))
  } else {
    r <- sample(3:8, 1); cc <- sample(3:7, 1); tb <- matrix(rpois(r * cc, 6) + 1, r); nd <- min(r, cc) - 1
    f <- CA(tb, graph = FALSE, ncp = nd); a <- c(1, r, cc, rowmajor(tb))
    add("ceig", a, ws(f$eig[seq_len(nd), 1])); add("rcoord", a, ws(abs(rowmajor(f$row$coord)))); add("rcontrib", a, ws(rowmajor(f$row$contrib)))
    add("ccoord", a, ws(abs(rowmajor(f$col$coord)))); add("ccos2", a, ws(rowmajor(f$col$cos2)))
  }
}
emit("factominer", "FactoMineR", list(cases))
