# qcapkg: QCA minimize() on a crisp truth table.
#   "pof" (relation 0 sufficiency 1 necessity, which 0 inclS or inclN, 1 PRI or RoN, 2 covS or covN, n, 3, length(spec), spec = nterms then per term the literal count and (column, negated) pairs, A B C row-major, OUT) is the fuzzy pof() of a sum of products.
#   args: (what 0 prime implicants (complex only) 1 minimum size 2 number of models, mode 0 complex 1 parsimonious, n, n_on, n_dc, on minterms..., dc minterms...)
suppressMessages(library(QCA))
cases <- list()
add <- function(fn, args, want, rel = 0) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = if (rel == 0) 0 else 1e-12)
set.seed(20262018)
for (rep in 1:60) {
  n <- sample(3:5, 1); tt <- expand.grid(rep(list(0:1), n)); names(tt) <- LETTERS[1:n]; tt$OUT <- sample(c(1, 0), nrow(tt), TRUE, prob = c(0.4, 0.6))
  mode <- rep %% 2; if (mode == 1) tt <- tt[sort(sample(nrow(tt), floor(nrow(tt) * runif(1, 0.5, 0.85)))), ]
  if (sum(tt$OUT) < 2 || sum(tt$OUT == 0) < 1) next
  on <- which(tt$OUT == 1); idx <- function(r) sum(as.numeric(r) * 2^((n - 1):0))
  mt <- sapply(on, function(i) idx(tt[i, 1:n]))
  full <- expand.grid(rep(list(0:1), n)); allm <- sapply(seq_len(nrow(full)), function(i) idx(full[i, ])); seen <- sapply(seq_len(nrow(tt)), function(i) idx(tt[i, 1:n]))
  dc <- if (mode == 1) setdiff(allm, seen) else integer(0)
  m <- tryCatch(minimize(truthTable(tt, outcome = "OUT", incl.cut = 1, show.cases = FALSE), include = if (mode == 1) "?" else "", details = TRUE), error = function(e) NULL)
  if (is.null(m) || length(m$solution) == 0 || is.null(m$PIchart)) next
  a <- c(mode, n, length(mt), length(dc), mt, dc)
  if (mode == 0) add("qca", c(0, a), nrow(m$PIchart))
  add("qca", c(1, a), length(m$solution[[1]])); add("qca", c(2, a), length(m$solution))
}
for (rep in 1:30) {
  n <- sample(10:40, 1); d <- data.frame(A = round(runif(n), 3), B = round(runif(n), 3), C = round(runif(n), 3), OUT = round(runif(n), 3))
  nt <- sample(1:2, 1); lits <- list(); spec <- c(nt); expr <- character(0)
  for (t in seq_len(nt)) { nl <- sample(1:3, 1); v <- sample(0:2, nl); ng <- sample(0:1, nl, TRUE); spec <- c(spec, nl, as.vector(rbind(v, ng))); expr <- c(expr, paste0(ifelse(ng == 1, "~", ""), c("A", "B", "C")[v + 1], collapse = "*")) }
  e <- paste(expr, collapse = " + ")
  if (nt == 2 && expr[1] == expr[2]) next
  for (rel in 0:1) { p <- pof(e, "OUT", d, relation = if (rel == 0) "sufficiency" else "necessity"); row <- p$incl.cov[nrow(p$incl.cov), ]
    for (w in 0:2) add("pof", c(rel, w, n, 3, length(spec), spec, as.vector(t(as.matrix(d[, 1:3]))), d$OUT), as.numeric(row[[w + 1]]), 1e-8) }
}
emit("qcapkg", "QCA", list(cases))
