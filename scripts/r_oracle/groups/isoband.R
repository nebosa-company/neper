# isoband: isolines and isobands over seeded grids (smooth, noisy, integer-valued with ties at the
# level, checkerboard saddles, NA cells, irregular spacing). Each answer is canonicalised the same
# way on both sides: a closed path starts at its smallest (x, y); paths are sorted by their
# coordinates, then by length; an open line keeps its direction.
#   args: (kind 0 band 1 line, lo, hi, nrow, ncol, x..., y..., z...)  (column-major z)
#   cases: "len:iso" the number of points, "v:ix", "v:iy" and "v:iid" the coordinates and the path number
library(isoband)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
vec <- function(name, args, v) {
  add(paste0("len:", name), args, length(v))
  for (i in seq_along(v)) add(paste0("v:", name), c(args, i - 1), v[i])
}
cmp_less <- function(a, b) {
  va <- c(t(a)); vb <- c(t(b))
  n <- min(length(va), length(vb))
  for (i in seq_len(n)) if (va[i] != vb[i]) return(va[i] < vb[i])
  length(va) < length(vb)
}
canon <- function(res, ring) {
  ids <- unique(res$id)
  paths <- lapply(ids, function(i) cbind(res$x[res$id == i], res$y[res$id == i]))
  paths <- lapply(paths, function(m) {
    n <- nrow(m)
    closed <- ring || (n > 2 && all(m[1, ] == m[n, ]))
    if (closed) {
      if (!ring) m <- m[-n, , drop = FALSE]
      o <- order(m[, 1], m[, 2])
      cand <- o[m[o, 1] == m[o[1], 1] & m[o, 2] == m[o[1], 2]]
      rot <- function(k) m[c(k:nrow(m), seq_len(k - 1)), , drop = FALSE]
      best <- rot(cand[1])
      for (k in cand[-1]) { r <- rot(k); if (cmp_less(r, best)) best <- r }
      m <- best
      if (!ring) m <- rbind(m, m[1, ])
    }
    m
  })
  if (length(paths) > 1) for (i in 2:length(paths)) {
    j <- i
    while (j > 1 && cmp_less(paths[[j]], paths[[j - 1]])) { t <- paths[[j]]; paths[[j]] <- paths[[j - 1]]; paths[[j - 1]] <- t; j <- j - 1 }
  }
  list(x = unlist(lapply(paths, function(m) m[, 1])), y = unlist(lapply(paths, function(m) m[, 2])),
       id = unlist(lapply(seq_along(paths), function(i) rep(i, nrow(paths[[i]])))))
}
fields <- list()
mk <- function(nr, nc, f, irregular = FALSE) {
  x <- if (irregular) sort(round(runif(nc, 0, 10), 3)) + seq_len(nc) * 0.01 else seq_len(nc) - 1
  y <- if (irregular) sort(round(runif(nr, 0, 10), 3)) + seq_len(nr) * 0.01 else seq_len(nr) - 1
  z <- outer(y, x, f)
  list(x = x, y = y, z = z)
}
for (nr in c(2, 4, 8)) for (nc in c(3, 7)) {
  fields[[length(fields) + 1]] <- mk(nr, nc, function(y, x) sin(x / 2.1) + cos(y / 1.7) + 0.2 * x * y / (nr * nc))
  fields[[length(fields) + 1]] <- list(x = seq_len(nc) - 1, y = seq_len(nr) - 1, z = matrix(round(runif(nr * nc, 0, 4)), nr, nc))
}
fields[[length(fields) + 1]] <- list(x = 0:3, y = 0:3, z = matrix(c(1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1), 4, 4))
fields[[length(fields) + 1]] <- list(x = 0:2, y = 0:2, z = matrix(c(0, 2, 0, 2, 0, 2, 0, 2, 0), 3, 3))
fields[[length(fields) + 1]] <- list(x = 0:2, y = 0:2, z = matrix(c(2, 0, 2, 0, 2, 0, 2, 0, 2), 3, 3))
fields[[length(fields) + 1]] <- list(x = 0:1, y = 0:1, z = matrix(c(2, 0, 0, 2), 2, 2))
fields[[length(fields) + 1]] <- list(x = 0:1, y = 0:1, z = matrix(c(0, 2, 2, 0), 2, 2))
for (k in 1:2) {
  f <- mk(7, 9, function(y, x) round(3 * sin(x * 0.7 + k) * cos(y * 0.6) + runif(1, 0, 0.5)), irregular = k %% 2 == 0)
  fields[[length(fields) + 1]] <- f
  g <- f; g$z[sample(length(g$z), 5)] <- NA; fields[[length(fields) + 1]] <- g
}
for (fl in fields) {
  nr <- nrow(fl$z); nc <- ncol(fl$z)
  rng <- range(fl$z, na.rm = TRUE)
  levels <- unique(c(rng[1] + diff(rng) * c(0.3, 0.6), round(mean(rng)), 1))
  levels <- levels[is.finite(levels)]
  base <- c(nr, nc, fl$x, fl$y, fl$z)
  for (lv in levels) {
    lo <- lv; hi <- lv + max(diff(rng) * 0.3, 0.5)
    for (kind in 0:1) {
      res <- tryCatch(if (kind == 0) isobands(fl$x, fl$y, fl$z, lo, hi)[[1]] else isolines(fl$x, fl$y, fl$z, lv)[[1]], error = function(e) NULL)
      if (is.null(res)) next
      cn <- canon(res, kind == 0)
      a <- c(kind, lo, hi, base)
      vec("iso", a, cn$x); vec("isoy", a, cn$y); vec("isoid", a, cn$id)
    }
  }
}
emit("isoband", "isoband", list(cases))
