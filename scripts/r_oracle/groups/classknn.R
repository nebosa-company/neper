# class: knn, knn1 and knn.cv under set.seed (ties are broken with the random stream).
#   args: (kind 0 knn 1 knn1 2 knn.cv, seed, k, l, use.all, p, ntr, nte, nc, cl[ntr], train row-wise, test row-wise, pos)
#   fn "cvsum" and "cvprob": the sums of class * position and prob * position over the knn.cv answer
#   fn "cls" (the class) and "prob" (the winning proportion, knn only)
library(class)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261115)
rowvec <- function(m) as.vector(t(m))
for (rep in 1:8) {
  p <- 1 + rep %% 3; ntr <- 20 + 5 * (rep %% 4); nte <- 6; nc <- 2 + rep %% 2
  grid <- rep %% 2 == 0
  mk <- function(n) { m <- matrix(rnorm(n * p, 0, 1.2), n, p); if (grid) round(m) else round(m, 3); }
  cl <- sample(nc, ntr, TRUE); tr <- mk(ntr) + matrix(cl, ntr, p) * 0.4; te <- mk(nte) + 0.6
  for (k in c(1, 3, 5)) for (l in c(0, 2)) for (ua in c(TRUE, FALSE)) {
    if (l > k) next
    seed <- sample(1e6, 1); set.seed(seed)
    r <- suppressWarnings(knn(tr, te, cl, k = k, l = l, prob = TRUE, use.all = ua))
    a <- c(0, seed, k, l, ua, p, ntr, nte, nc, cl, rowvec(tr), rowvec(te))
    for (i in 1:nte) { add("cls", c(a, i - 1), as.integer(r)[i]); add("prob", c(a, i - 1), attr(r, "prob")[i]) }
    set.seed(seed); r <- suppressWarnings(knn.cv(tr, cl, k = k, l = l, prob = TRUE, use.all = ua))
    a2 <- c(2, seed, k, l, ua, p, ntr, ntr, nc, cl, rowvec(tr), rowvec(tr))
    add("cvsum", a2, sum(as.integer(r) * seq_along(r))); add("cvprob", a2, sum(attr(r, "prob") * seq_along(r)))
  }
  seed <- sample(1e6, 1); set.seed(seed)
  r <- knn1(tr, te, cl); a <- c(1, seed, 1, 0, 1, p, ntr, nte, nc, cl, rowvec(tr), rowvec(te))
  for (i in 1:nte) add("cls", c(a, i - 1), as.integer(r)[i])
}
emit("classknn", "class", list(cases))
