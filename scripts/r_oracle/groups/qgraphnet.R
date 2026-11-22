# qgraph: centrality_auto on general graphs (directed, unweighted, disconnected), centralityTable, mat2vec, FDRnetwork and the spring layout.
#   fn "cent_between" "cent_clos" "cent_clos_na" "cent_outstr" "cent_instr" "cent_outei" "cent_inei" "cent_spl" "cent_spl_inf" "cent_eb" "cent_eb_ord" "cent_ne"
#     args (n, weighted, signed, W[n*n] column-major): position-weighted sums of the node measures (NA counted as 0, its positions in cent_clos_na),
#     of the finite shortest path lengths (infinite positions in cent_spl_inf), of the edge betweenness table in qgraph's order (cent_eb), of
#     from * 100 + to along that table (cent_eb_ord), and the table length (cent_ne)
#   fn "tab_<measure>" "tab_<measure>_na": args (n, weighted, signed, standardized, relative, W): centralityTable's values of one measure
#   fn "m2v_len" "m2v_sum": args (n, diag, tol, X column-major)
#   fn "fdr_sum": args (method 0 lfdr, 1 pval, 2 qval, cutoff, n, net column-major)
#   fn "sp_raw_x" "sp_raw_y" "sp_x" "sp_y": args (n, niter, repulsion, area (-1 default), cool (-1 default), W): $layout.orig and $layout of qgraph(layout = "spring")
suppressMessages(library(qgraph))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(ifelse(is.na(v), 0, v) * seq_along(v))
nas <- function(v) sum(is.na(v) * seq_along(v))
vecs <- c("between", "clos", "outstr", "instr", "outei", "inei")
rgraph <- function(n, kind) {
  w <- matrix(0, n, n)
  dens <- runif(1, 0.2, 0.6)
  if (kind %in% c("und", "unw", "disc")) {
    ut <- upper.tri(w)
    w[ut] <- ifelse(runif(sum(ut)) < dens, round(runif(sum(ut), -0.9, 0.9), 2), 0)
    if (kind == "disc") { k <- sample(2:(n - 1), 1); w[1:k, (k + 1):n] <- 0 }
    w <- w + t(w)
  } else {
    w[] <- ifelse(runif(n * n) < dens, round(runif(n * n, -0.9, 0.9), 2), 0)
    diag(w) <- 0
  }
  w[w == -0] <- 0
  if (kind %in% c("unw", "dunw")) w <- (w != 0) * 1
  w
}
mapping <- function(r, directed) {
  nc <- r$node.centrality
  if (directed) list(between = nc$Betweenness, clos = nc$Closeness, outstr = if (!is.null(nc$OutStrength)) nc$OutStrength else nc$OutDegree,
                     instr = if (!is.null(nc$InStrength)) nc$InStrength else nc$InDegree, outei = nc$OutExpectedInfluence, inei = nc$InExpectedInfluence)
  else list(between = nc$Betweenness, clos = nc$Closeness, outstr = if (!is.null(nc$Strength)) nc$Strength else nc$Degree,
            instr = if (!is.null(nc$Strength)) nc$Strength else nc$Degree, outei = nc$ExpectedInfluence, inei = nc$ExpectedInfluence)
}
set.seed(20271201)
kinds <- rep(c("und", "unw", "disc", "dir", "dunw"), length.out = 45)
for (it in seq_along(kinds)) {
  kind <- kinds[it]; n <- sample(4:13, 1)
  w <- rgraph(n, kind)
  if (all(w == 0)) next
  wg <- !(it %% 7 == 0); sg <- !(it %% 11 == 0)
  r <- suppressWarnings(centrality_auto(w, weighted = wg, signed = sg))
  x <- w; if (!wg) x <- sign(x); if (!sg) x <- abs(x); diag(x) <- 0
  directed <- !isSymmetric(unname(x), tol = 1e-12)
  m <- mapping(r, directed)
  a <- c(n, wg, sg, as.vector(w))
  for (nm in vecs) { add(paste0("cent_", nm), a, ws(m[[nm]])); if (nm == "clos") add("cent_clos_na", a, nas(m[[nm]]), rel = 0, abs = 0) }
  sp <- r$ShortestPathLengths
  add("cent_spl", a, ws(ifelse(is.finite(sp), sp, 0))); add("cent_spl_inf", a, ws(is.infinite(sp) * 1), rel = 0, abs = 0)
  eb <- r$edge.betweenness.centrality
  add("cent_ne", a, nrow(eb), rel = 0, abs = 0)
  if (nrow(eb) > 0) { add("cent_eb", a, ws(eb$edgebetweenness)); add("cent_eb_ord", a, ws(eb$from * 100 + eb$to), rel = 0, abs = 0) }
  if (it %% 3 == 0) {
    st <- it %% 2 == 0; rl <- it %% 4 == 0
    tb <- suppressWarnings(centralityTable(w, standardized = st, relative = rl, weighted = wg, signed = sg))
    strn <- if ("Strength" %in% names(r$node.centrality)) "Strength" else "Degree"
    getm <- function(nm) tb$value[tb$measure == nm]
    nmv <- if (directed) c(between = "Betweenness", clos = "Closeness", outstr = if ("OutStrength" %in% names(r$node.centrality)) "OutStrength" else "OutDegree", instr = if ("InStrength" %in% names(r$node.centrality)) "InStrength" else "InDegree", outei = "OutExpectedInfluence", inei = "InExpectedInfluence")
           else c(between = "Betweenness", clos = "Closeness", outstr = strn, instr = strn, outei = "ExpectedInfluence", inei = "ExpectedInfluence")
    ta <- c(n, wg, sg, st, rl, as.vector(w))
    for (nm in vecs) {
      v <- getm(nmv[[nm]])
      add(paste0("tab_", nm), ta, ws(v)); add(paste0("tab_", nm, "_na"), ta, nas(v), rel = 0, abs = 0)
    }
  }
}
# mat2vec
for (it in 1:40) {
  n <- sample(2:7, 1); x <- matrix(round(rnorm(n * n), 3), n, n)
  kind <- it %% 4
  if (kind != 0) x <- (x + t(x)) / 2
  tol <- c(1e-10, 1e-6, 1e-12, 0.01)[1 + it %% 4]
  if (kind == 2) { x[1, 2] <- x[1, 2] + 3e-9 }
  if (kind == 3) { x[2, 1] <- x[2, 1] + 0.5 * tol * mean(abs(x)) }
  dg <- it %% 3 == 0
  v <- mat2vec(x, diag = dg, tol = tol)
  a <- c(n, dg, tol, as.vector(x))
  add("m2v_len", a, length(v), rel = 0, abs = 0); add("m2v_sum", a, ws(v), rel = 1e-12)
}
# FDRnetwork
for (it in 1:24) {
  p <- sample(5:16, 1); n <- sample(60:300, 1)
  A <- matrix(rnorm(p * p), p, p); L <- diag(p) + c(0.3, 1, 2)[1 + it %% 3] * A %*% t(A) / p
  x <- matrix(rnorm(n * p), n, p) %*% chol(L); net <- cor(x)
  method <- c("lfdr", "pval", "qval")[1 + it %% 3]; cutoff <- c(0.1, 0.05, 0.2, 0.5)[1 + it %% 4]
  r <- tryCatch(suppressWarnings(FDRnetwork(net, cutoff = cutoff, method = method)), error = function(e) NULL)
  if (is.null(r)) next
  add("fdr_sum", c(it %% 3, cutoff, p, as.vector(net)), ws(r), rel = 1e-8)
}
# spring layout
for (it in 1:30) {
  n <- sample(4:12, 1); kind <- c("und", "dir", "und")[1 + it %% 3]
  w <- rgraph(n, kind); if (all(w == 0)) next
  ni <- if (it %% 4 == 0) sample(50:200, 1) else 500; rep <- c(1, 1, 0.5, 2)[1 + it %% 4]
  ar <- if (it %% 5 == 0) n^2 * 2 else -1; cl <- if (it %% 6 == 0) 2 else -1
  lp <- list(niter = ni, repulse.rad = n^(rep * 3))
  if (ar > 0) lp$area <- ar; if (cl > 0) lp$cool.exp <- cl
  q <- suppressWarnings(qgraph(w, layout = "spring", layout.par = lp, DoNotPlot = TRUE))
  a <- c(n, ni, rep, ar, cl, as.vector(w))
  add("sp_raw_x", a, ws(q$layout.orig[, 1])); add("sp_raw_y", a, ws(q$layout.orig[, 2]))
  add("sp_x", a, ws(q$layout[, 1])); add("sp_y", a, ws(q$layout[, 2]))
}
emit("qgraphnet", "qgraph", list(cases))
