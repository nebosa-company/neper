# clue: cl_consensus(method = "GV3") (sumt with optim CG on |Y - M M'|^2), hard and soft ensembles, one and several runs.
#   "gv3" (B, n, k, nruns, seed, w[B], memberships B by n by k row-major): the checksum sum(M * (10 * row + column)) of the consensus membership; set.seed(seed) precedes the call
suppressMessages(library(clue))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
tight <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-13, abs = 1e-13)
chk <- function(M, n, k) sum(M * outer(seq_len(n), seq_len(k), function(i, j) 10 * i + j))
set.seed(20262491)
for (rep in 1:30) {
  B <- sample(3:5, 1); n <- sample(8:16, 1); k <- sample(2:3, 1); nruns <- if (rep %% 3 == 0) 2 else 1
  w <- runif(B, 0.5, 3); soft <- rep %% 2 == 0
  Ms <- lapply(seq_len(B), function(b) {
    if (soft) { M <- matrix(rexp(n * k), n, k); M / rowSums(M) } else {
      lab <- c(seq_len(k), sample(seq_len(k), n - k, replace = TRUE)); fl <- sample(n, sample(1:4, 1)); lab[fl] <- sample(seq_len(k), length(fl), TRUE); lab[seq_len(k)] <- seq_len(k)
      M <- matrix(0, n, k); M[cbind(seq_len(n), lab)] <- 1; M } })
  ens <- as.cl_ensemble(lapply(Ms, as.cl_partition))
  if (any(sapply(ens, n_of_classes) != k)) next
  Ms <- lapply(ens, function(x) matrix(as.numeric(unclass(cl_membership(x, k))), n))  # as clue holds them (as.cl_partition renormalises rows)
  # the stages: the eigen start m (column-major) and the first CG call of sumt at its first penalty weight
  wn <- w / sum(w)
  Y <- clue:::.weighted_sum_of_matrices(lapply(Ms, tcrossprod), wn, n)
  e <- eigen(Y, symmetric = TRUE); m0 <- c(e$vectors[, seq_len(k), drop = FALSE] * rep(sqrt(e$values[seq_len(k)]), each = n))
  y <- c(Y); Lf <- function(m) sum((y - tcrossprod(matrix(m, n))) ^ 2); Pf <- clue:::.make_penalty_function_membership(n, k)
  gL <- function(m) { M <- matrix(m, n); 4 * c((tcrossprod(M) - Y) %*% M) }; gP <- clue:::.make_penalty_gradient_membership(n, k)
  rho <- max(Lf(m0), 0.00001) / max(Pf(m0), 0.00001)
  seed <- sample(1000:99999, 1); set.seed(seed)
  a0 <- c(B, n, k, 1, seed, w, unlist(lapply(Ms, function(M) as.vector(t(M)))))
  tight("gv3m0", a0, sum(m0 * seq_along(m0)))
  xx <- m0; rr <- rho
  for (t in 1:6) {  # the first t calls of sumt's inner optimisation, "gv3cg" with the number of calls in the nruns slot
    xo <- xx
    xx <- optim(xx, function(m) Lf(m) + rr * Pf(m), gr = function(m) gL(m) + rr * gP(m), method = "CG")$par
    if (t %in% c(1, 2, 3, 6)) tight("gv3cg", c(B, n, k, t, seed, w, unlist(lapply(Ms, function(M) as.vector(t(M))))), sum(xx * seq_along(xx)))
    if (max(abs(xo - xx)) < sqrt(.Machine$double.eps)) break
    rr <- 10 * rr
  }
  sx <- clue:::sumt(list(m0), Lf, Pf, gL, gP)$x
  tight("gv3x", a0, sum(sx * seq_along(sx)))
  set.seed(seed)
  res <- tryCatch(cl_consensus(ens, method = "GV3", weights = w, control = list(nruns = nruns)), error = function(e) NULL)
  if (is.null(res)) next
  add("gv3", c(B, n, k, nruns, seed, w, unlist(lapply(Ms, function(M) as.vector(t(M))))), chk(matrix(as.numeric(unclass(cl_membership(res, k))), n), n, k))
}
emit("clue_gv3", "clue", list(cases))
