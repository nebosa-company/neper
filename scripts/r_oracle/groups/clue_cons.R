# clue: cl_consensus of partitions ("SE" from a given start, "DWH" in the given order), of hclust trees ("majority"), and cl_medoid, against e.algo.stat.cluecons.
#   "se" (B, n, k, w[B], start n by k row-major, labels B by n): sum over the consensus membership of entry * (10 * row + column)
#   "dwh" (B, n, k, w[B], labels B by n): the same checksum
#   "maj" (B, n, w[B], method[B], points B by n by 2): sum over the n by n ultrametric of entry * (7 * i + 3 * j + 1), i and j 1-based
#   "medoid" (B, n, k, labels B by n): the 1-based index of cl_medoid's choice
suppressMessages(library(clue))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
set.seed(20262420)
chk <- function(M, n, k) sum(M * outer(seq_len(n), seq_len(k), function(i, j) 10 * i + j))
mk <- function(lab) as.cl_partition(factor(lab))
for (rep in 1:40) {
  B <- sample(3:6, 1); n <- sample(10:30, 1); k <- sample(2:4, 1)
  labs <- t(sapply(seq_len(B), function(b) { kb <- sample(2:k, 1); c(seq_len(kb), sample(seq_len(kb), n - kb, replace = TRUE)) }))
  if (!any(apply(labs, 1, max) == k)) labs[1, 1:k] <- seq_len(k)
  # make partitions noisy copies of one base so the consensus is non trivial
  base <- c(seq_len(k), sample(seq_len(k), n - k, replace = TRUE))
  for (b in seq_len(B)) { labs[b, ] <- base; flip <- sample(n, sample(1:4, 1)); labs[b, flip] <- sample(seq_len(k), length(flip), TRUE); labs[b, ] <- as.integer(factor(labs[b, ])) }
  if (any(apply(labs, 1, function(r) length(unique(r))) < 1)) next
  w <- round(runif(B, 0.5, 3), 2)
  st <- matrix(runif(n * k), n, k); st <- st / rowSums(st)
  ens <- as.cl_ensemble(lapply(seq_len(B), function(b) mk(labs[b, ])))
  kk <- max(sapply(ens, n_of_classes))
  if (kk != k) next
  res <- cl_consensus(ens, method = "SE", weights = w, control = list(start = st))
  add("se", c(B, n, k, w, as.vector(t(st)), as.vector(t(labs))), chk(matrix(as.numeric(unclass(cl_membership(res, k))), n), n, k))
  res <- cl_consensus(ens, method = "DWH", weights = w, control = list(order = seq_len(B)))
  add("dwh", c(B, n, k, w, as.vector(t(labs))), chk(matrix(as.numeric(unclass(cl_membership(res, k))), n), n, k))
  med <- cl_medoid(ens)
  add("medoid", c(B, n, k, as.vector(t(labs))), which(sapply(ens, function(e) identical(unclass(cl_class_ids(e)), unclass(cl_class_ids(med))))) [1])
}
meth <- c("ward.D", "single", "complete", "average", "mcquitty", "median", "centroid", "ward.D2")
for (rep in 1:40) {
  B <- sample(3:6, 1); n <- sample(6:20, 1)
  x0 <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); w <- round(runif(B, 0.5, 3), 2)
  mm <- sample(c(1, 2, 3, 4, 5, 8), B, TRUE)
  pts <- lapply(seq_len(B), function(b) x0 + matrix(round(rnorm(n * 2, 0, 0.5), 3), n, 2))
  hs <- lapply(seq_len(B), function(b) hclust(dist(pts[[b]]), meth[mm[b]]))
  res <- tryCatch(cl_consensus(as.cl_ensemble(hs), method = "majority", weights = w), error = function(e) NULL)
  if (is.null(res)) next
  d <- as.matrix(cl_ultrametric(res))
  add("maj", c(B, n, w, mm, unlist(lapply(pts, function(p) as.vector(t(p))))), sum(d * outer(seq_len(n), seq_len(n), function(i, j) 7 * i + 3 * j + 1)))
}
# the alternating optimisation methods SE, HE, SM, HM (kind 0 .. 3) on ensembles of hard or soft partitions, from given starts or R's own random starts:
#   "ao" (kind, nruns, seed, B, n, k, w[B], memberships B by n by k row-major, [starts nruns by n by k row-major when seed is 0]): the checksum of the consensus membership
#   seed above 0: set.seed(seed) then control = list(nruns = nruns), so the starts are runif draws in R's order (a column-major n by k matrix, rows scaled to one)
mname <- c("SE", "HE", "SM", "HM")
aocase <- function(kind, nruns, seed, B, n, k, w, Ms, starts) {
  ens <- as.cl_ensemble(lapply(Ms, function(M) as.cl_partition(M)))
  if (any(sapply(ens, n_of_classes) != k)) return(invisible())
  if (seed > 0) { set.seed(seed); ctl <- list(nruns = nruns) } else ctl <- list(start = starts)
  if (nruns > 1) {
    # runs reaching the same criterion value by a different column order are chosen by rounding noise: leave those programs out
    if (seed > 0) { set.seed(seed); st2 <- replicate(nruns, { S <- matrix(runif(n * k), n, k); S / rowSums(S) }, simplify = FALSE) } else st2 <- starts
    vals <- sapply(st2, function(S) attr(unclass(cl_consensus(ens, method = mname[kind + 1], weights = w, control = list(start = list(S))))$.Data, "meta")$objval)
    sv <- sort(vals)
    if (any(diff(sv) < 1e-6 * (1 + abs(sv[-1])) & diff(sv) >= 0)) {
      one <- lapply(st2, function(S) as.numeric(unclass(cl_membership(cl_consensus(ens, method = mname[kind + 1], weights = w, control = list(start = list(S))), k))))
      if (length(unique(round(unlist(lapply(one, function(m) chk(matrix(m, n), n, k))), 6))) > 1) return(invisible())
    }
  }
  if (seed > 0) set.seed(seed)
  res <- tryCatch(cl_consensus(ens, method = mname[kind + 1], weights = w, control = ctl), error = function(e) NULL)
  if (is.null(res)) return(invisible())
  a <- c(kind, nruns, seed, B, n, k, w, unlist(lapply(Ms, function(M) as.vector(t(M)))))
  if (seed == 0) a <- c(a, unlist(lapply(starts, function(S) as.vector(t(S)))))
  add("ao", a, chk(matrix(as.numeric(unclass(cl_membership(res, k))), n), n, k))
  if (seed == 0 && nruns > 1) for (r in seq_len(nruns)) {  # each run alone
    r1 <- cl_consensus(ens, method = mname[kind + 1], weights = w, control = list(start = starts[r]))
    add("ao", c(kind, 1, 0, B, n, k, w, unlist(lapply(Ms, function(M) as.vector(t(M)))), as.vector(t(starts[[r]]))), chk(matrix(as.numeric(unclass(cl_membership(r1, k))), n), n, k))
  }
}
hardM <- function(lab, n, k) { M <- matrix(0, n, k); M[cbind(seq_len(n), lab)] <- 1; M }
for (rep in 1:72) {
  kind <- rep %% 4; B <- sample(3:5, 1); n <- sample(8:20, 1); k <- sample(2:4, 1)
  w <- runif(B, 0.5, 3)  # unrounded: equal weight sums make the L1 fit of SM and HM ties that lp_solve breaks by its own path
  soft <- rep %% 8 >= 4 && kind != 2  # soft SM inputs tie the L1 fit across columns (a flat face), where lp_solve picks a vertex by its own path
  Ms <- lapply(seq_len(B), function(b) {
    if (soft) { M <- matrix(rexp(n * k), n, k); M / rowSums(M) } else {
      base <- c(seq_len(k), sample(seq_len(k), n - k, replace = TRUE)); lab <- base
      flip <- sample(n, sample(1:4, 1)); lab[flip] <- sample(seq_len(k), length(flip), TRUE)
      lab[seq_len(k)] <- seq_len(k); hardM(lab, n, k) } })
  nruns <- sample(1:3, 1)
  if (rep %% 2 == 0) {
    starts <- lapply(seq_len(nruns), function(r) { S <- matrix(runif(n * k), n, k); S / rowSums(S) })
    aocase(kind, nruns, 0, B, n, k, w, Ms, starts)
  } else aocase(kind, nruns, sample(1000:99999, 1), B, n, k, w, Ms, NULL)
}
emit("clue_cons", "clue", list(cases))
