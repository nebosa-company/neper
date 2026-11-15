# abind: arrays of rank 1 to 4 (a rank-1 shape is a plain vector) bound along dimensions 1..N+1,
# between them (0.5, 1.5, ...), counted from the end (rev.along), with force.array on and off.
# A case is (along, rev.along, force, number of arrays, then rank and dims of each array) and
# element index e: e >= 0 is the e-th element of the column-major result, and the fn
# "abind_dim" answers dimension e (1-based, 0 = the rank). Array j holds 1000 j + 1, 1000 j + 2, ...
library(abind)

make <- function(shape, j) {
  x <- 1000 * j + seq_len(prod(shape))
  if (length(shape) > 1) dim(x) <- shape
  x
}

scenarios <- list(
  list(3, 3), list(2, 2, 2), list(5), list(3, 1), list(2, 4),
  list(c(2, 3), c(2, 3)), list(c(2, 3), c(4, 3)), list(c(2, 3), c(2, 5)), list(c(2, 3), c(2, 3), c(2, 3)),
  list(c(1, 3), c(2, 3)), list(c(2, 3), 3), list(c(2, 3), 2), list(c(2, 1), c(2, 4)), list(c(3, 3), c(3, 3)),
  list(c(2, 3, 4), c(2, 3, 4)), list(c(2, 3, 4), c(2, 3, 1)), list(c(2, 3, 4), c(2, 4)), list(c(2, 3, 4), c(3, 4)),
  list(c(2, 3, 4), c(2, 1, 4), c(2, 2, 4)), list(c(2, 2, 2, 2), c(2, 2, 2, 2)), list(c(2, 2, 2), c(2, 2, 2, 3))
)
alongs <- c(1, 2, 3, 4, 0, 0.5, 1.5, 2.5, 3.5, 5)
revs <- c(NA, 1, 2)

cases <- list()
for (sc in scenarios) for (along in alongs) for (rev in revs) for (force in c(TRUE, FALSE)) {
  if (!is.na(rev) && along != 1) next
  arrays <- Map(make, sc, seq_along(sc))
  res <- tryCatch(suppressWarnings(do.call(abind, c(arrays, list(along = along, force.array = force,
                                                                   rev.along = if (is.na(rev)) NULL else rev)))),
                  error = function(e) NULL)
  if (is.null(res)) next
  shape <- lapply(sc, length)
  head <- c(along, rev, force, length(sc), unlist(Map(function(s) c(length(s), s), sc)))
  d <- if (is.null(dim(res))) length(res) else dim(res)
  cases[[length(cases) + 1]] <- case("abind_dim", c(head, 0), length(d), rel = 0, abs = 0)
  for (k in seq_along(d)) cases[[length(cases) + 1]] <- case("abind_dim", c(head, k), d[k], rel = 0, abs = 0)
  v <- as.vector(res)
  for (e in seq_along(v)) cases[[length(cases) + 1]] <- case("abind", c(head, e - 1), v[e], rel = 0, abs = 0)
}
emit("abind", "abind", list(cases))
