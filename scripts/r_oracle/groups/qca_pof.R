# qca_pof: QCA pof() of a sum of products, per term, with the unique coverage and a negated outcome.
#   args: (relation 0 sufficiency 1 necessity, which 0 inclS or inclN, 1 PRI or RoN, 2 covS or covN, 3 covU (sufficiency), term (0-based; the number of terms is the whole expression), neg.out 0 1, n, nv, length(spec),
#          spec = nterms then per term the literal count and (column, negated) pairs, A B C row-major, OUT)
suppressMessages(library(QCA))
cases <- list()
set.seed(20262803)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pof", args, want, rel = 1e-10, abs = 1e-12)
for (rep in 1:38) {
  n <- sample(10:40, 1); nv <- sample(3:4, 1); d <- as.data.frame(matrix(round(runif(n * nv), 3), n, nv)); names(d) <- LETTERS[1:nv]; d$OUT <- round(runif(n), 3)
  nt <- sample(1:3, 1); spec <- c(nt); expr <- character(0)
  for (t in seq_len(nt)) { nl <- sample(1:min(3, nv), 1); v <- sample(0:(nv - 1), nl); ng <- sample(0:1, nl, TRUE); spec <- c(spec, nl, as.vector(rbind(v, ng))); expr <- c(expr, paste0(ifelse(ng == 1, "~", ""), LETTERS[v + 1], collapse = "*")) }
  if (length(unique(expr)) < nt) next
  e <- paste(expr, collapse = " + "); neg <- sample(0:1, 1)
  for (rel in 0:1) {
    p <- tryCatch(suppressWarnings(pof(e, "OUT", d, relation = if (rel == 0) "sufficiency" else "necessity", neg.out = neg == 1)), error = function(e) NULL)
    if (is.null(p)) next
    m <- p$incl.cov; nr <- if (nt == 1) 1 else nt + 1
    for (term in 0:(nr - 1)) for (w in 0:(if (rel == 0) 3 else 2)) {
      v <- m[term + 1, w + 1]
      if (is.na(v)) next
      add(c(rel, w, term, neg, n, nv, length(spec), spec, as.vector(t(as.matrix(d[, 1:nv]))), d$OUT), v)
    }
  }
}
emit("qca_pof", "QCA", list(cases))
