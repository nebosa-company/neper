# spdep neighbours, listw and the global and local tests, built from random point sets.
#   args: header (kind, p1, p2, style, self, n, co[2n]) then, per family, x[n] and its parameters.
#   kind 0 knn2nb(knearneigh(co, p1)), 1 dnearneigh(co, p1, p2), 2 tri2nb, 3 symmetrised knn; style 0 W 1 B 2 C 3 U 4 S; self 1 adds the diagonal.
#   families (fn): nb, lw (checksums of the neighbour and weight matrices), moran (rand, rank, dropei2, alt, idx), geary (rand, alt, idx),
#   G (alt, idx), lmoran (cond, mlvar, adjx, alt, idx), lG (star, alt, idx), jc (lev, sampling, alt, idx), mc (nsim, seed, alt, idx);
#   a vector result is the checksum sum(v * (1 + (i - 1) / 7)).
suppressMessages(library(spdep))
cases <- list()
add <- function(fn, args, want, rel = 1e-10, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
cs <- function(v) sum(v * (1 + (seq_along(v) - 1) / 7))
styles <- c("W", "B", "C", "U", "S")
alts <- c("greater", "less", "two.sided")
set.seed(20261222)
for (rep in 1:11) {
  n <- sample(14:26, 1); co <- matrix(runif(2 * n), n)
  kind <- c(0, 1, 2, 3, 0, 1, 2, 3, 1, 0, 2)[rep]
  p1 <- 0; p2 <- 0
  if (kind == 0 || kind == 3) p1 <- sample(2:5, 1)
  if (kind == 1) { dm <- as.matrix(dist(co)); diag(dm) <- Inf; p2 <- median(apply(dm, 1, min)) * 1.3; p1 <- if (rep %% 2) 0 else p2 / 4 }
  sty <- (rep - 1) %% 5
  nb <- switch(kind + 1, knn2nb(knearneigh(co, k = p1)), dnearneigh(co, p1, p2), tri2nb(co), make.sym.nb(knn2nb(knearneigh(co, k = p1))))
  H <- c(kind, p1, p2, sty, 0, n, as.vector(t(co)))
  lw <- nb2listw(nb, style = styles[sty + 1], zero.policy = TRUE)
  W <- listw2mat(lw)
  A <- matrix(0, n, n); for (i in 1:n) if (nb[[i]][1] != 0) A[i, nb[[i]]] <- 1
  w <- outer(1:n, 1:n)
  add("nb", c(H, 0), sum(A * w))
  add("lw", c(H, 0), sum(W * (w %% 97 + 0.5)))
  x <- rnorm(n) + co[, 1] * 2
  xp <- exp(x / 2)
  iso <- any(card(nb) == 0)
  for (r in 0:1) {
    m <- moran.test(x, lw, randomisation = r == 1, alternative = alts[(rep + r) %% 3 + 1], zero.policy = TRUE)
    out <- c(m$estimate, m$statistic, m$p.value)
    for (k in 0:4) add("moran", c(H, x, r, 0, 0, (rep + r) %% 3, k), out[k + 1])
    g <- geary.test(x, lw, randomisation = r == 1, alternative = alts[(rep + r + 1) %% 3 + 1], zero.policy = TRUE)
    out <- c(g$estimate, g$statistic, g$p.value)
    for (k in 0:4) add("geary", c(H, x, r, (rep + r + 1) %% 3, k), out[k + 1])
  }
  m <- moran.test(x, lw, randomisation = TRUE, rank = TRUE, drop.EI2 = TRUE, alternative = "two.sided", zero.policy = TRUE)
  out <- c(m$estimate, m$statistic, m$p.value)
  for (k in 0:4) add("moran", c(H, x, 1, 1, 1, 2, k), out[k + 1])
  gg <- suppressWarnings(globalG.test(xp, lw, alternative = alts[rep %% 3 + 1], zero.policy = TRUE))
  out <- c(gg$estimate, gg$statistic, gg$p.value)
  for (k in 0:4) add("G", c(H, xp, rep %% 3, k), out[k + 1])
  fx <- cut(x, c(-Inf, quantile(x, c(0.4, 0.75)), Inf), labels = FALSE)
  for (s in 0:1) {
    jc <- joincount.test(factor(fx), lw, sampling = c("nonfree", "free")[s + 1], alternative = alts[(rep + s) %% 3 + 1], zero.policy = TRUE)
    for (lev in 1:2) {
      j <- jc[[lev]]; out <- c(j$estimate, j$statistic, j$p.value)
      for (k in 0:4) add("jc", c(H, fx, lev, s, (rep + s) %% 3, k), out[k + 1])
    }
  }
  for (cf in list(c(1, 1, 0), c(0, 0, 0), c(1, 0, if (iso) 1 else 0))) {
    alt <- (rep + cf[1] + cf[2]) %% 3
    lm_ <- localmoran(x, lw, zero.policy = TRUE, conditional = cf[1] == 1, mlvar = cf[2] == 1, adjust.x = cf[3] == 1, alternative = alts[alt + 1])
    for (k in 0:4) add("lmoran", c(H, x, cf, alt, k), cs(lm_[, k + 1]))
  }
  nsim <- 99; sd <- sample(1:100000, 1)
  set.seed(sd)
  mc <- moran.mc(x, lw, nsim = nsim, alternative = alts[rep %% 3 + 1], zero.policy = TRUE)
  add("mc", c(H, x, nsim, sd, rep %% 3, 0), cs(mc$res))
  add("mc", c(H, x, nsim, sd, rep %% 3, 1), mc$statistic)
  add("mc", c(H, x, nsim, sd, rep %% 3, 2), mc$parameter)
  add("mc", c(H, x, nsim, sd, rep %% 3, 3), mc$p.value)
  if (!iso) {
    lg <- localG(x, lw, alternative = alts[rep %% 3 + 1], zero.policy = TRUE)
    ints <- attr(lg, "internals")
    for (k in 0:4) add("lG", c(H, x, 0, rep %% 3, k), cs(ints[, k + 1]))
    if (kind != 1) {
      Hs <- H; Hs[5] <- 1
      lws <- nb2listw(include.self(nb), style = styles[sty + 1], zero.policy = TRUE)
      lg <- localG(x, lws, alternative = alts[(rep + 1) %% 3 + 1])
      ints <- attr(lg, "internals")
      for (k in 0:4) add("lG", c(Hs, x, 1, (rep + 1) %% 3, k), cs(ints[, k + 1]))
    }
  }
}
# poly2nb: fn "poly", args (queen, n, snap, vertex counts[n], vertices as x y pairs after dropping the first row of each ring, as spdep does)
suppressMessages({library(sf); library(deldir)})
snap0 <- sqrt(.Machine$double.eps)
polycase <- function(rings, jit) {
  rings <- lapply(rings, function(r) { r <- r + matrix(runif(length(r), -jit, jit), nrow(r)); r })
  sfc <- st_sfc(lapply(rings, function(r) st_polygon(list(rbind(r, r[1, ])))))
  xx <- lapply(rings, function(r) rbind(r[-1, , drop = FALSE], r[1, ]))
  pts <- unlist(lapply(xx, function(m) as.vector(t(m))))
  for (queen in c(TRUE, FALSE)) {
    nb <- poly2nb(sfc, queen = queen)
    n <- length(rings); A <- matrix(0, n, n)
    for (i in 1:n) if (nb[[i]][1] != 0) A[i, nb[[i]]] <- 1
    add("poly", c(queen, n, snap0, sapply(xx, nrow), pts), sum(A * outer(1:n, 1:n)))
  }
}
for (rep in 1:3) {
  np <- sample(10:18, 1); dd <- deldir(runif(np), runif(np), suppressMsgs = TRUE)
  polycase(lapply(tile.list(dd), function(t) cbind(t$x, t$y)), 0)
}
for (jit in c(0, 4e-9, 1.2e-8, 4e-9)) {
  nc <- sample(3:5, 1); nr <- sample(3:4, 1)
  xs <- c(0, cumsum(runif(nc, 0.5, 1.5))); ys <- c(0, cumsum(runif(nr, 0.5, 1.5)))
  keep <- sample(c(TRUE, FALSE), nc * nr, TRUE, prob = c(0.75, 0.25)); keep[1] <- TRUE; keep[2] <- TRUE
  rings <- list(); id <- 0
  for (i in 1:nc) for (j in 1:nr) { id <- id + 1; if (keep[id]) rings[[length(rings) + 1]] <- cbind(c(xs[i], xs[i + 1], xs[i + 1], xs[i]), c(ys[j], ys[j], ys[j + 1], ys[j + 1])) }
  polycase(rings, jit)
}
emit("spdepnb", "spdep", list(cases))
