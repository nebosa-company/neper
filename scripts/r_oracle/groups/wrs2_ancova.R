# WRS2::ancova (two groups, trimmed means 0.2, fr1 = fr2 = 1): the evaluated covariate points, the counts, the trimmed-mean difference, its standard error, the test and the p value.
# Args: (nx1, nx2, npts, row, what, pts[npts], x1[nx1], y1[nx1], x2[nx2], y2[nx2]); what 0 evalpt, 1 n1, 2 n2, 3 diff, 4 se, 5 test, 6 p value; row 0-based.
suppressMessages(library(WRS2))
cases <- list()
set.seed(20261803)
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("a", args, want, rel = 1e-7, abs = 1e-9)
for (rep in 1:5) {
  n1 <- sample(45:70, 1); n2 <- sample(40:60, 1)
  x1 <- round(rnorm(n1, 0, 1), 3); y1 <- round(1 + 0.8 * x1 + rnorm(n1, 0, 0.8), 3)
  x2 <- round(rnorm(n2, 0.2, 1.1), 3); y2 <- round(1.4 + 0.3 * x2 + rnorm(n2, 0, 1), 3)
  d <- data.frame(y = c(y1, y2), g = factor(rep(c("A", "B"), c(n1, n2))), x = c(x1, x2))
  pts <- if (rep %% 2 == 0) c(-0.5, 0, 0.7) else NULL
  r <- if (is.null(pts)) ancova(y ~ g + x, data = d) else ancova(y ~ g + x, data = d, pts = pts)
  for (i in seq_along(r$evalpts)) {
    hdr <- function(w) c(n1, n2, length(pts), i - 1, w, pts, x1, y1, x2, y2)
    add(hdr(0), r$evalpts[i]); add(hdr(1), r$n1[i]); add(hdr(2), r$n2[i]); add(hdr(3), r$trDiff[i]); add(hdr(4), r$se[i]); add(hdr(5), r$test[i]); add(hdr(6), r$p.vals[i])
  }
}
emit("wrs2_ancova", "WRS2", list(cases))
