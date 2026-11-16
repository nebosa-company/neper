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
emit("isotone", "isotone", list(cases))
