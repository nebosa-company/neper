# igraph force-directed and spectral layouts: layout_with_fr (random start, nogrid), layout_with_kk, layout_with_graphopt, layout_with_mds.
# A layout is summarised as the sum and the row-weighted sum of each coordinate column.
#   fn "<alg>_<col><s|w>" with alg fr kk go mds, col x y z; args: (seed, n, ne, hasw, p1..p6, edges (0-based, as_edgelist order) [2*ne], weights [ne when hasw])
#   fr: p1 niter, p2 start.temp; kk: p1 maxiter, p2 epsilon, p3 kkconst; go: p1 niter, p2 charge, p3 mass, p4 spring.length, p5 spring.constant, p6 max.sa.movement; mds: p1 dim
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want, tol) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = tol / 10)
lay <- function(alg, g, p, seed, w, tol) {
  n <- vcount(g); e <- as_edgelist(g, names = FALSE) - 1; ne <- nrow(e)
  hasw <- !is.null(w)
  hdr <- c(seed, n, ne, hasw, p, rep(0, 6 - length(p)), as.vector(t(e)), if (hasw) w)
  m <- do.call(rbind, list())
  set.seed(seed)
  m <- switch(alg,
    fr = layout_with_fr(g, niter = p[1], start.temp = p[2], grid = "nogrid", weights = w),
    fg = layout_with_fr(g, niter = p[1], start.temp = p[2], grid = "grid", weights = w),
    kk = layout_with_kk(g, maxiter = p[1], epsilon = p[2], kkconst = p[3], weights = w),
    go = layout_with_graphopt(g, niter = p[1], charge = p[2], mass = p[3], spring.length = p[4], spring.constant = p[5], max.sa.movement = p[6]),
    mds = layout_with_mds(g, dim = p[1]),
    md = layout_with_mds(g, dim = 2))
  # Kamada-Kawai keeps its gradient by incremental updates, so where it ends depends on rounding when the problem is ill-conditioned: a start nudged by
  # one ulp moves R itself by up to 1e-7. A case where R moves by more than 1e-10 under such a nudge is compared at 1e-6, the rest at 1e-9.
  if (alg == "kk") {
    phi <- 2 * pi / n * (0:(n - 1)); st <- cbind(cos(phi), sin(phi)) * (0.36 * sqrt(n)); sp <- 0
    for (t in 1:4) { s2 <- st * (1 + sample(c(-1, 0, 1), 2 * n, TRUE) * 2.2e-16); sp <- max(sp, max(abs(m - layout_with_kk(g, coords = s2, maxiter = p[1], epsilon = p[2], kkconst = p[3], weights = w)))) }
    if (sp > 1e-10) tol <- max(tol, 1e-6)
  }
  for (k in seq_len(ncol(m))) {
    col <- c("x", "y", "z")[k]
    add(paste0(alg, "_", col, "s"), hdr, sum(m[, k]), tol); add(paste0(alg, "_", col, "w"), hdr, sum(seq_len(n) * m[, k]), tol)
  }
}
conn <- function(n, p) { repeat { g <- sample_gnp(n, p); if (is_connected(g) && ecount(g) > 0) return(g) } }
set.seed(20261121)
sd <- 5000
nxt <- function() { sd <<- sd + 1; sd }
for (rep in 1:10) {
  n <- sample(5:18, 1); g <- sample_gnp(n, runif(1, 0.15, 0.5)); if (ecount(g) == 0) next
  w <- if (rep %% 3 == 0) round(runif(ecount(g), 0.5, 2), 3) else NULL
  lay("fr", g, c(c(50, 500)[rep %% 2 + 1], sqrt(n) * c(1, 0.5)[(rep %/% 2) %% 2 + 1]), nxt(), w, 1e-9)
}
for (rep in 1:10) {
  n <- sample(5:18, 1); g <- conn(n, runif(1, 0.2, 0.5))
  w <- if (rep %% 3 == 0) round(runif(ecount(g), 0.5, 2), 3) else NULL
  # an early stop at epsilon 0.1 sits on the slow part of the iteration, where R itself moves by 2e-7 when the start is nudged by one ulp
  e1 <- c(0, 0.1)[rep %% 2 + 1]; lay("kk", g, c(50 * n, e1, c(n, 2)[(rep %/% 2) %% 2 + 1]), nxt(), w, if (e1 > 0) 1e-6 else 1e-9)
  if (!is.null(w)) for (eps in c(0, 0.1, 1e-4)) lay("kk", g, c(50 * n, eps, n), nxt(), w, if (eps >= 0.1) 1e-6 else 1e-9)
  lay("go", g, c(c(50, 500)[rep %% 2 + 1], c(0.001, 0.0005, 0)[rep %% 3 + 1], c(30, 10)[(rep %/% 2) %% 2 + 1], c(0, 0.5)[rep %% 2 + 1], c(1, 2)[(rep %/% 2) %% 2 + 1], 5), nxt(), NULL, 1e-9)
  # twin vertices (equal neighbourhoods) make the sign dstein picks for an eigenvector depend on ulp-level ties, so such graphs are left out
  A <- as.matrix(as_adjacency_matrix(g)); if (!anyDuplicated(A) && !anyDuplicated(A + diag(n))) lay("mds", g, c(2 + (rep %% 2)), nxt(), NULL, 1e-9)
}
# fr with the grid (what igraph runs above 1000 vertices; asked for here by grid = "grid"): repulsion only inside neighbouring cells
for (rep in 1:12) {
  n <- sample(c(20:60, 100:140), 1); g <- sample_gnp(n, runif(1, 1, 3) / n); if (ecount(g) == 0) next
  w <- if (rep %% 3 == 0) round(runif(ecount(g), 0.5, 2), 3) else NULL
  lay("fg", g, c(c(50, 500)[rep %% 2 + 1], sqrt(n) * c(1, 0.5)[(rep %/% 2) %% 2 + 1]), nxt(), w, 1e-9)
}
# mds on a disconnected graph: components laid out one by one, then merged by DLA over the random stream (components whose eigenvalues are separated)
# the top two eigenvectors of the double-centred squared distances are only defined where the eigenvalues are separated, so a component whose
# 2nd and 3rd (or 1st and 2nd) eigenvalue sit within 1e-3 of each other is left out, as is one with a vanishing 2nd eigenvalue (a path is a line): R answers there with whatever rounding picks
gapok <- function(h) { nh <- vcount(h); if (nh < 3) return(TRUE); D <- distances(h)^2; J <- diag(nh) - 1 / nh; v <- eigen(-0.5 * J %*% D %*% J, symmetric = TRUE, only.values = TRUE)$values; (v[1] - v[2]) > 1e-3 * v[1] && (v[2] - v[3]) > 1e-3 * v[2] && v[2] > 1e-6 * v[1] }
ntw <- function(g) { cm <- components(g); all(vapply(seq_len(cm$no), function(k) gapok(induced_subgraph(g, which(cm$membership == k))), TRUE)) }
for (rep in 1:14) {
  repeat { n <- sample(8:45, 1); g <- sample_gnp(n, runif(1, 0.5, 2) / n); if (components(g)$no >= 2 && ecount(g) > 0 && ntw(g)) break }
  lay("md", g, c(2), nxt(), NULL, 1e-9)
}
# connected graphs that do have twin vertices (equal neighbourhoods), where the eigenvalues are still separated
for (rep in 1:30) {
  n <- sample(6:30, 1); g <- conn(n, runif(1, 0.1, 0.4))
  A <- as.matrix(as_adjacency_matrix(g)); if (!(anyDuplicated(A) || anyDuplicated(A + diag(n))) || !gapok(g)) next
  lay("mds", g, c(2), nxt(), NULL, 1e-9)
}
emit("igraph_layouts", "igraph", list(cases))
