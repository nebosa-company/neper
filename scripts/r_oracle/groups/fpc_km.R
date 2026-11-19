# stats::kmeans (Hartigan-Wong), fpc::kmeansruns and fpc::pamk under set.seed.
#   "km": (fn, what, n, p, k1, k2, crit, iter.max, runs, scale, nstart, seed, flag, data n by p row-major, or the n by n dissimilarities for pamk with diss)
#   fn 1 kmeans(x, k1, iter.max, nstart): what 0 sum i * cluster[i], 1 tot.withinss, 2 totss, 3 iter, 4 sum (row * p + col) * centers (1-based), 5 sum j * withinss[j],
#       6 sum j * size[j], 7 ifault
#   fn 2 kmeansruns(x, krange = k1:k2, criterion crit 0 ch / 1 asw, iter.max, runs, scaledata, nstart): what 0 bestk, 1 sum k * crit[k], 2 as kmeans 0, 3 tot.withinss,
#       4 centers, 5 iter, 6 totss
#   fn 3 pamk(x, krange = k1:k2, criterion crit 0 asw / 1 multiasw (ns = runs, seed) / 2 ch, scaling = scale, diss = flag): what 0 nc, 1 sum k * crit[k], 2 sum i * clustering[i],
#       3 sum j * medoids[j] (the medoid row numbers)
suppressMessages(library(fpc))
cases <- list()
set.seed(20267301)
blobs <- function(n, p, k, sd = 0.8) {
  m <- rep(n %/% k, k); m[1] <- m[1] + n - sum(m); ctr <- matrix(runif(k * p, 0, 7), k, p)
  round(do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p, 0, sd), m[g], p) + rep(ctr[g, ], each = m[g]))), 4)
}
add <- function(hdr, v, rel = 1e-9, ab = 1e-9) cases[[length(cases) + 1]] <<- case("km", hdr, v, rel = rel, abs = ab)
wsum <- function(v) sum(seq_along(v) * v)
for (rep in 1:14) {
  k <- sample(2:5, 1); n <- sample(25:60, 1); p <- sample(2:4, 1)
  x <- blobs(n, p, k, c(0.8, 2.5)[rep %% 2 + 1])
  if (rep == 13) x <- rbind(x, x[1:6, ])
  n <- nrow(x)
  kk <- c(2, 3, 4, 5, 3, 6, 2)[rep %% 7 + 1]; itm <- c(10, 1, 2, 20)[rep %% 4 + 1]; ns <- c(1, 1, 2, 3)[rep %% 4 + 1]; seed <- 700 + rep
  set.seed(seed)
  r <- try(kmeans(x, kk, iter.max = itm, nstart = ns), silent = TRUE)
  if (inherits(r, "try-error")) next
  hdr <- c(1, 0, n, p, kk, 0, 0, itm, 0, 0, ns, seed, 0, as.vector(t(x)))
  h <- function(w) { z <- hdr; z[2] <- w; z }
  add(h(0), wsum(r$cluster)); add(h(1), r$tot.withinss); add(h(2), r$totss); add(h(3), r$iter)
  add(h(4), sum(seq_len(kk * p) * as.vector(t(r$centers)))); add(h(5), wsum(r$withinss)); add(h(6), wsum(r$size)); add(h(7), r$ifault)
}
for (rep in 1:12) {
  k <- sample(2:4, 1); n <- sample(30:60, 1); p <- sample(2:3, 1)
  x <- blobs(n, p, k, 1)
  one <- rep %% 3 == 0
  k1 <- if (one) 1 else 2; k2 <- sample(4:6, 1); cr <- rep %% 2; runs <- c(1, 4, 8)[rep %% 3 + 1]; sc <- rep %% 4 == 1; ns <- c(1, 2)[(rep %/% 2) %% 2 + 1]; seed <- 800 + rep
  set.seed(seed)
  r <- kmeansruns(x, krange = k1:k2, criterion = c("ch", "asw")[cr + 1], iter.max = 50, runs = runs, scaledata = sc, nstart = ns)
  hdr <- c(2, 0, n, p, k1, k2, cr, 50, runs, as.numeric(sc), ns, seed, 0, as.vector(t(x)))
  h <- function(w) { z <- hdr; z[2] <- w; z }
  add(h(0), r$bestk)
  add(h(1), sum(seq_along(r$crit) * r$crit), rel = 1e-9, ab = 1e-9)
  if (r$bestk >= 2) {
    add(h(2), wsum(r$cluster)); add(h(3), r$tot.withinss); add(h(4), sum(seq_len(r$bestk * p) * as.vector(t(r$centers)))); add(h(5), r$iter); add(h(6), r$totss)
  }
}
for (rep in 1:12) {
  k <- sample(2:4, 1); n <- sample(25:50, 1); p <- sample(2:3, 1)
  x <- blobs(n, p, k, 1)
  diss <- rep %% 4 == 3
  k1 <- if (rep %% 3 == 0 && !diss) 1 else 2; k2 <- sample(4:6, 1); cr <- c(0, 2, 1)[rep %% 3 + 1]; if (diss && cr == 1) cr <- 0
  sc <- rep %% 2 == 1 && !diss; seed <- 900 + rep
  set.seed(seed)
  r <- pamk(if (diss) dist(x) else x, krange = k1:k2, criterion = c("asw", "multiasw", "ch")[cr + 1], scaling = sc, diss = diss, ns = 4, seed = seed)
  dat <- if (diss) as.vector(t(as.matrix(dist(x)))) else as.vector(t(x))
  hdr <- c(3, 0, n, p, k1, k2, cr, 0, 4, as.numeric(sc), 0, seed, as.numeric(diss), dat)
  h <- function(w) { z <- hdr; z[2] <- w; z }
  add(h(0), r$nc); add(h(1), sum(seq_along(r$crit) * r$crit))
  if (r$nc >= 2) { add(h(2), wsum(r$pamobject$clustering)); add(h(3), wsum(r$pamobject$id.med)) }
}
emit("fpc_km", "fpc", list(cases))
