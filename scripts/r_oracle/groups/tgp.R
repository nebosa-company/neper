# tgp: lhs(), the Latin hypercube sampler, which draws from tgp's own randomkit Mersenne-Twister.
# fn "lh" calls the C entry point lh_sample directly with an explicit integer state; fn "lhs" calls
# the R function lhs() under set.seed (its state is sample(seq(0,999),3)).
# Args: state (3 ints for "lh", the seed for "lhs"), n, d, rect (d lows then d highs), shape (d), mode (d),
# element index k of the n x d row-major block (point i, dimension j is k = i d + j). shape -1 is the uniform form.
library(tgp)

configs <- list(
  list(n = 5, d = 1, rect = c(0, 1)),
  list(n = 10, d = 2, rect = matrix(c(0, -2, 1, 3), 2)),
  list(n = 8, d = 3, rect = matrix(c(-1, 0, 5, 1, 4, 9), 3)),
  list(n = 20, d = 2, rect = matrix(c(0, 0, 10, 100), 2))
)
shapes <- list(
  list(shape = c(2), mode = c(0.3)),
  list(shape = c(3, 0.5), mode = c(0.5, 1)),
  list(shape = c(2, 5, 0), mode = c(0.2, 3, 0.7)),
  list(shape = c(4, 1.5), mode = c(5, 20))
)
states <- list(c(0, 0, 0), c(123, 456, 789), c(999, 999, 999), c(7, 31, 500))
seeds <- c(1, 42, 2024)

args_of <- function(s, cfg, shape, mode, k) c(s, cfg$n, cfg$d, as.double(cfg$rect), shape, mode, k)

cases <- list()
for (ci in seq_along(configs)) {
  cfg <- configs[[ci]]
  d <- cfg$d
  uni <- list(shape = rep(-1, d), mode = rep(-1, d))
  bet <- shapes[[ci]]
  for (st in states) {
    for (sm in list(uni, bet)) {
      out <- .C("lh_sample", state = as.integer(st), n = as.integer(cfg$n), d = as.integer(d),
                rect = as.double(cfg$rect), shape = as.double(sm$shape), mode = as.double(sm$mode),
                s = double(cfg$n * d), PACKAGE = "tgp")$s
      rel <- if (sm$shape[1] < 0) 0 else 1e-12; ab <- if (sm$shape[1] < 0) 0 else 1e-13
      for (k in seq_along(out))
        cases[[length(cases) + 1]] <- list(case("lh", args_of(st, cfg, sm$shape, sm$mode, k - 1), out[k], rel = rel, abs = ab))
    }
  }
  for (sd in seeds) {
    for (sm in list(uni, bet)) {
      set.seed(sd)
      res <- if (sm$shape[1] < 0) lhs(cfg$n, cfg$rect) else lhs(cfg$n, cfg$rect, shape = sm$shape, mode = sm$mode)
      out <- as.vector(t(matrix(res, nrow = cfg$n)))
      rel <- if (sm$shape[1] < 0) 0 else 1e-12; ab <- if (sm$shape[1] < 0) 0 else 1e-13
      for (k in seq_along(out))
        cases[[length(cases) + 1]] <- list(case("lhs", args_of(c(sd, 0, 0), cfg, sm$shape, sm$mode, k - 1), out[k], rel = rel, abs = ab))
    }
  }
}

emit("tgp", "tgp", cases)
