# MASS loglm (the formula reduced to generating margins, loglin's iterative proportional fitting, statistics, degrees of freedom, parameters).
#   "loglm" (nvar, nt, eps, iter, mode, dims[nvar], tmask[nt] (variable bit sets of the formula terms in terms() order), table[N] col-major, start[N])
#   mode 0 lrt, 1 pearson, 2 df, 3 position-weighted sum of the fitted table, 4 sum_j j * (bit set of margin j), 5 position-weighted sum of the unlisted param, 6 its length
suppressMessages(library(MASS))
cases <- list()
add <- function(args, want, rel = 1e-9, abs = 1e-10) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case("loglm", args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262902)
vn <- c("a", "b", "c", "d")
pool <- list(
  c("~a+b", "~a*b"),
  c("~a+b+c", "~a*b+c", "~a*b+b*c", "~a*b*c", "~a:b+c", "~a*b+a*c+b*c", "~a:b+b:c", "~a+b:c"),
  c("~a*b+c*d", "~a*b*c+d", "~a+b+c+d", "~a*b+b*c+c*d", "~a*b*c+b*d", "~a*b+c+d"))
for (rep in 1:80) {
  nv <- sample(2:4, 1); dims <- sample(2:4, nv, TRUE); if (nv == 4) dims <- sample(2:3, 4, TRUE)
  N <- prod(dims); tab <- rpois(N, runif(1, 2, 12)); start <- rep(1, N)
  if (rep %% 4 == 1) start <- round(runif(N, 0.5, 2), 3)
  if (rep %% 4 == 2) { z <- sample(N, max(1, N %/% 10)); start[z] <- 0; tab[z] <- 0 }
  dn <- setNames(lapply(dims, function(k) paste0("l", seq_len(k))), vn[seq_len(nv)])
  A <- array(tab, dim = dims, dimnames = dn); class(A) <- "table"
  fo <- as.formula(sample(pool[[nv - 1]], 1))
  eps <- c(0.1, 1e-3, 1e-8, 0.5)[rep %% 4 + 1]; it <- c(40, 4, 1, 100)[rep %% 3 + 1]
  f <- tryCatch(suppressWarnings(loglm(fo, data = A, start = start, fitted = TRUE, param = TRUE, eps = eps, iter = it, print = FALSE)), error = function(e) NULL)
  if (is.null(f)) next
  tl <- attr(terms(fo), "term.labels")
  tm <- vapply(strsplit(tl, ":"), function(p) sum(2^(match(p, vn) - 1)), 0)
  mm <- vapply(f$margin, function(m) sum(2^(match(m, vn) - 1)), 0)
  a <- c(nv, length(tm), eps, it); tail <- c(dims, tm, tab, start)
  add(c(a, 0, tail), f$lrt); add(c(a, 1, tail), f$pearson); add(c(a, 2, tail), f$df, 0, 0)
  add(c(a, 3, tail), wsum(f$fitted)); add(c(a, 4, tail), wsum(mm), 0, 0)
  pr <- unlist(f$param)
  if (all(is.finite(pr))) { add(c(a, 5, tail), wsum(pr), 1e-8, 1e-9); add(c(a, 6, tail), length(pr), 0, 0) }
}
emit("mass_loglm", "MASS", list(cases))
