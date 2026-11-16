# qcapkg: QCA minimize() on a crisp truth table.
#   args: (what 0 prime implicants (complex only) 1 minimum size 2 number of models, mode 0 complex 1 parsimonious, n, n_on, n_dc, on minterms..., dc minterms...)
suppressMessages(library(QCA))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
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
emit("qcapkg", "QCA", list(cases))
