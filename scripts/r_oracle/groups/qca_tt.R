# QCA: truthTable() with inclusion, n and PRI cut-offs on crisp and fuzzy data. Args: (n, nv, k, incl.cut, n.cut, pri.cut, c, what, data[n * nv] row-major, the k conditions first and the outcome last):
# configuration c (0-based, first condition the most significant bit), what 0 n, 1 incl, 2 PRI, 3 OUT (-1 for the "?" row); incl and PRI of an empty configuration are not compared.
suppressMessages(library(QCA))
cases <- list()
set.seed(20262333)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("tt", args, want, rel = 1e-10, abs = 1e-12)
for (rep in 1:20) {
  n <- sample(20:40, 1); k <- sample(3:4, 1); fuzzy <- rep %% 2 == 0
  X <- matrix(if (fuzzy) round(runif(n * k), 3) else rbinom(n * k, 1, 0.5), n, k); y <- if (fuzzy) round(pmin(1, pmax(0, X[, 1] * 0.7 + runif(n, 0, 0.5))), 3) else rbinom(n, 1, 0.5)
  d <- data.frame(X, Y = y); names(d) <- c(LETTERS[1:k], "Y")
  ic <- sample(c(0.6, 0.8, 1), 1); nc <- sample(1:2, 1); pc <- sample(c(0, 0.3), 1)
  tt <- tryCatch(suppressWarnings(truthTable(d, outcome = "Y", conditions = LETTERS[1:k], incl.cut = ic, n.cut = nc, pri.cut = pc)), error = function(e) NULL)
  if (is.null(tt)) next
  t <- unclass(tt)$tt; rows <- 2^k
  if (nrow(t) != rows) next
  for (c in 0:(rows - 1)) {
    a <- function(w) c(n, k + 1, k, ic, nc, pc, c, w, as.vector(t(cbind(X, y))))
    add(a(0), as.numeric(t$n[c + 1])); add(a(3), if (t$OUT[c + 1] == "?") -1 else as.numeric(t$OUT[c + 1]))
    if (t$n[c + 1] > 0) { add(a(1), as.numeric(t$incl[c + 1])); add(a(2), as.numeric(t$PRI[c + 1])) }
  }
}
emit("qca_tt", "QCA", list(cases))
