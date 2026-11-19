# fpc: dudahart2, con.comp, stupidkcentroids / stupidknn / stupidkfn / stupidkaven, distcritmulti, cvnn, mahalanodisc.
#   "dh": (n, p, alpha, what, cl[n] in 1:2, x row-major); what 0 p.value 1 dh 2 compare 3 cluster1 4 z
#   "cc": (nc, comat nc by nc row-major 0/1); the answer is sum((i + 1) * ccn[i])
#   "sk": (mode, n, k, seed, d n by n row-major): mode 0 stupidkcentroids (distances), 1 stupidknn, 2 stupidkfn, 3 stupidkaven; the answer is sum(i * clustering[i])
#   "dcm": (n, p, ns, crit, seed, what, cl[n], x row-major): crit 0 asw 1 pearsongamma; what 0 crit.overall, 1 crit.sd, 2 sum(i * crit.sub[i])
#   "cv": (n, k, lc, what, d n by n row-major, clusterings lc by n row-major); what 0 cvnnindex, 1 sep, 2 comp; the answer is sum(i * value[i])
#   "mh": (n, p, md, what, mg[p], cov p by p, x row-major); the answer is sum(i * distance[i])
suppressMessages(library(fpc))
cases <- list()
set.seed(20269961)
flat <- function(m) as.vector(t(unclass(as.matrix(m))))
add <- function(nm, args, want, rel = 1e-9, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = rel, abs = abs)
for (rep in 1:14) {
  p <- sample(1:4, 1); n <- sample(10:60, 1); cl <- sample(1:2, n, TRUE); cl[1:2] <- 1:2
  x <- matrix(rnorm(n * p) + cl * (rep %% 3), n, p); alpha <- c(0.001, 0.01, 0.05)[rep %% 3 + 1]
  r <- dudahart2(x, cl, alpha = alpha)
  for (w in 0:4) add("dh", c(n, p, alpha, w, cl, flat(x)), c(r$p.value, r$dh, r$compare, as.numeric(r$cluster1), r$z)[w + 1])
}
for (rep in 1:12) {
  nc <- sample(2:12, 1); cm <- matrix(runif(nc * nc) < c(0.1, 0.2, 0.3)[rep %% 3 + 1], nc, nc)
  if (rep %% 2 == 0) cm <- cm | t(cm)
  add("cc", c(nc, as.numeric(flat(cm))), sum((seq_len(nc)) * con.comp(cm)))
}
for (rep in 1:16) {
  n <- sample(8:40, 1); k <- sample(2:4, 1); X <- matrix(rnorm(n * 2), n, 2); d <- as.matrix(dist(X)); mode <- rep %% 4; seed <- 500 + rep
  set.seed(seed)
  cl <- switch(mode + 1, stupidkcentroids(d, k, distances = TRUE)$partition, stupidknn(d, k), stupidkfn(d, k), stupidkaven(d, k))
  add("sk", c(mode, n, k, seed, flat(d)), sum(seq_len(n) * cl), rel = 0, abs = 0)
}
for (rep in 1:10) {
  n <- sample(30:70, 1); p <- sample(2:3, 1); k <- sample(2:4, 1); cl <- sample(1:k, n, TRUE); cl[1:k] <- 1:k
  x <- matrix(rnorm(n * p) + cl, n, p); ns <- sample(2:4, 1); crit <- rep %% 2; seed <- 600 + rep
  r <- distcritmulti(x, cl, ns = ns, criterion = c("asw", "pearsongamma")[crit + 1], seed = seed)
  for (w in 0:2) add("dcm", c(n, p, ns, crit, seed, w, cl, flat(x)), c(r$crit.overall, r$crit.sd, sum(seq_len(ns) * r$crit.sub))[w + 1])
}
set.seed(20269962)
for (rep in 1:8) {
  n <- sample(15:45, 1); k <- sample(3:6, 1); X <- matrix(rnorm(n * 2), n, 2); d <- as.matrix(dist(X)); lc <- sample(2:4, 1)
  cls <- lapply(seq_len(lc), function(i) { m <- sample(2:5, 1); c <- sample(m, n, TRUE); c[1:m] <- 1:m; c })
  r <- cvnn(d, cls, k = k)
  for (w in 0:2) add("cv", c(n, k, lc, w, flat(d), unlist(cls)), sum(seq_len(lc) * list(r$cvnnindex, r$sep, r$comp)[[w + 1]]))
}
for (rep in 1:10) {
  p <- sample(1:4, 1); n <- sample(5:30, 1); mg <- rnorm(p); A <- matrix(rnorm(p * p), p, p); S <- crossprod(A) + diag(p); x2 <- matrix(rnorm(n * p), n, p)
  md <- rep %% 2
  r <- mahalanodisc(x2, mg, S, modus = c("square", "md")[md + 1])
  add("mh", c(n, p, md, 0, mg, flat(S), flat(x2)), sum(seq_along(r) * r))
}
emit("fpc_misc", "fpc", list(cases))
