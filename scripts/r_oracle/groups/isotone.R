# isotone::gpava for a vector y: solvers weighted mean, weighted median, weighted fractile; ties primary, secondary, tertiary.
#   args: (solver 0 mean 1 median 2 fractile, p, ties 0 primary 1 secondary 2 tertiary, n, x[n], y[n], w[n], stat)  fn "stat": 0 length 1 sum 2 position-weighted sum 3 first 4 last
suppressMessages(library(isotone))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
set.seed(20261116)
for (rep in 1:60) {
  n <- sample(5:40, 1); x <- if (rep %% 2 == 0) sample(1:round(n * 0.6), n, TRUE) else sample(n); y <- round(rnorm(n, 0, 1) + 0.05 * x, 3); w <- round(runif(n, 0.5, 3), 2)
  for (sv in 0:2) for (tie in 0:2) {
    if (length(unique(x)) == n && tie > 0) next
    p <- c(0, 0.5, 0.25)[sv + 1]; if (sv == 2) p <- c(0.25, 0.75)[rep %% 2 + 1]
    solver <- switch(sv + 1, weighted.mean, weighted.median, function(y, w) weighted.fractile(y, w, p))
    r <- tryCatch(gpava(x, y, w, solver = solver, ties = c("primary", "secondary", "tertiary")[tie + 1])$x, error = function(e) NULL)
    if (is.null(r)) next
    v <- as.numeric(r); a <- c(sv, p, tie, n, x, y, w)
    st <- c(length(v), sum(v), sum(seq_along(v) * v), v[1], v[length(v)])
    for (j in 0:4) add("stat", c(a, j), st[j + 1])
  }
}
# activeSet LS on a random partial order: ("as", n, m, y[n], w[n], isomat col1[m], col2[m], stat) stat 0 fval 1 niter 2 sum(pos*x) 3 sum(pos*lambda)
for (rep in 1:60) {
  n <- sample(4:9, 1); y <- round(rnorm(n), 3); w <- round(runif(n, 0.5, 3), 2); perm <- sample(n); ed <- NULL
  for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.3) ed <- rbind(ed, c(perm[i], perm[j]))
  if (is.null(ed)) next
  r <- tryCatch(suppressWarnings(activeSet(ed, "LS", y = y, weights = w, check = FALSE)), error = function(e) NULL)
  if (is.null(r) || r$niter >= 100 || any(is.na(r$lambda)) || any(is.na(r$x))) next
  a <- c(n, nrow(ed), y, w, ed[, 1], ed[, 2]); st <- c(r$fval, r$niter, sum(seq_along(r$x) * r$x), sum(seq_along(r$lambda) * r$lambda))
  for (j in 0:3) add("as", c(a, j), st[j + 1])
  r <- tryCatch(suppressWarnings(activeSet(ed, "L1", y = y, weights = w, check = FALSE)), error = function(e) NULL)
  if (is.null(r) || r$niter >= 100 || any(is.na(r$lambda)) || any(is.na(r$x))) next
  st <- c(r$fval, r$niter, sum(seq_along(r$x) * r$x), sum(seq_along(r$lambda) * r$lambda))
  for (j in 0:3) add("ad", c(a, j), st[j + 1])
}
for (rep in 1:40) {
  n <- sample(4:9, 1); y <- round(rnorm(n), 3); w <- round(runif(n, 0.5, 3), 2); perm <- sample(n); ed <- NULL; aw <- round(runif(1, 0.3, 2), 2); bw <- round(runif(1, 0.3, 2), 2)
  for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.3) ed <- rbind(ed, c(perm[i], perm[j]))
  if (is.null(ed)) next
  r <- tryCatch(suppressWarnings(activeSet(ed, "quantile", y = y, weights = w, aw = aw, bw = bw, check = FALSE)), error = function(e) NULL)
  if (is.null(r) || r$niter >= 100 || any(is.na(r$lambda)) || any(is.na(r$x))) next
  a <- c(n, nrow(ed), y, w, ed[, 1], ed[, 2]); st <- c(r$fval, r$niter, sum(seq_along(r$x) * r$x), sum(seq_along(r$lambda) * r$lambda))
  for (j in 0:3) add("aq", c(a, j, aw, bw), st[j + 1])
}
# activeSet with the optim(BFGS) solvers on random partial orders: names aa asyLS (aw, bw), ae L1eps (eps), ah huber (eps), ai SILF (eps, beta), ao Lp (p); args as aq
for (rep in 1:40) {
  n <- sample(4:8, 1); y <- round(rnorm(n), 3); w <- round(runif(n, 0.5, 3), 2); perm <- sample(n); ed <- NULL
  for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.3) ed <- rbind(ed, c(perm[i], perm[j]))
  if (is.null(ed)) next
  a <- c(n, nrow(ed), y, w, ed[, 1], ed[, 2])
  for (sv in c("aa", "ae", "ah", "ai", "ao")) {
    p1 <- round(runif(1, 0.3, 2), 2); p2 <- round(runif(1, 0.3, 2), 2)
    r <- tryCatch(suppressWarnings(switch(sv,
      aa = activeSet(ed, "asyLS", y = y, weights = w, aw = p1, bw = p2, check = FALSE),
      ae = activeSet(ed, "L1eps", y = y, weights = w, eps = p1, check = FALSE),
      ah = activeSet(ed, "huber", y = y, weights = w, eps = p1, check = FALSE),
      ai = activeSet(ed, "SILF", y = y, weights = w, eps = p1, beta = min(p2, 0.9), check = FALSE),
      ao = activeSet(ed, "Lp", y = y, weights = w, p = 1.2 + p1))), error = function(e) NULL)
    if (is.null(r) || r$niter >= 100 || any(is.na(r$lambda)) || any(is.na(r$x))) next
    if (sv == "ai") p2 <- min(p2, 0.9)
    if (sv == "ao") p1 <- 1.2 + p1
    st <- c(r$fval, r$niter, sum(seq_along(r$x) * r$x), sum(seq_along(r$lambda) * r$lambda))
    # SILF has a flat floor of minimisers: its fitted values depend on the last bit of the line search, the value and the iteration count do not
    for (j in (if (sv == "ai") 0:1 else 0:3)) cases[[length(cases) + 1]] <- case(sv, c(a, j, p1, p2), st[j + 1], rel = 1e-9, abs = 1e-10)
  }
}
# gpava with a matrix response (rows are repeated measurements): ("rows") args (solver 0 mean 1 median 2 fractile, p, ties, n, k, x[n], y row-major [n * k], w row-major [n * k], stat)
for (rep in 1:40) {
  n <- sample(5:25, 1); k <- sample(2:3, 1); x <- if (rep %% 2 == 0) sample(1:round(n * 0.6), n, TRUE) else sample(n); Y <- matrix(round(rnorm(n * k, 0, 1) + 0.08 * x, 3), n, k); W <- matrix(round(runif(n * k, 0.5, 3), 2), n, k)
  for (sv in 0:2) for (tie in 0:2) {
    if (length(unique(x)) == n && tie > 0) next
    p <- c(0, 0.5, 0.25)[sv + 1]; if (sv == 2) p <- c(0.25, 0.75)[rep %% 2 + 1]
    solver <- switch(sv + 1, weighted.mean, weighted.median, function(y, w) weighted.fractile(y, w, p))
    r <- tryCatch(gpava(x, Y, W, solver = solver, ties = c("primary", "secondary", "tertiary")[tie + 1])$x, error = function(e) NULL)
    if (is.null(r)) next
    v <- as.numeric(r); a <- c(sv, p, tie, n, k, x, as.vector(t(Y)), as.vector(t(W)))
    st <- c(length(v), sum(v), sum(seq_along(v) * v), v[1], v[length(v)])
    for (j in 0:4) cases[[length(cases) + 1]] <- case("rows", c(a, j), st[j + 1], rel = 1e-10, abs = 1e-12)
  }
}
# activeSet Poisson (sSolver) on positive responses: ap, args as aq; the statistic is j in 0:3
set.seed(20262340)
for (rep in 1:30) {
  n <- sample(4:8, 1); y <- round(abs(rnorm(n)) + 0.5, 3); w <- round(runif(n, 0.5, 3), 2); perm <- sample(n); ed <- NULL
  for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.3) ed <- rbind(ed, c(perm[i], perm[j]))
  if (is.null(ed)) next
  a <- c(n, nrow(ed), y, w, ed[, 1], ed[, 2])
  r <- tryCatch(suppressWarnings(activeSet(ed, "Poisson", y = y, weights = w, check = FALSE)), error = function(e) NULL)
  if (is.null(r) || r$niter >= 100 || any(is.na(r$lambda)) || any(is.na(r$x))) next
  st <- c(r$fval, r$niter, sum(seq_along(r$x) * r$x), sum(seq_along(r$lambda) * r$lambda))
  for (j in 0:3) cases[[length(cases) + 1]] <- case("ap", c(a, j, 1, 1), st[j + 1], rel = 1e-9, abs = 1e-10)
}
emit("isotone", "isotone", list(cases))
