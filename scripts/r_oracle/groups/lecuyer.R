# L'Ecuyer-CMRG: set.seed, runif, nextRNGStream and nextRNGSubStream.
#   args: (seed, jumps = number of stream jumps, subjumps = number of substream jumps, i)   the i-th (0-based) of 6 runif draws after the jumps
#   fn "u"; fn "state": (seed, jumps, subjumps, k) the k-th word of the state (unsigned) after the jumps
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-15, abs = 0)
uns <- function(v) ifelse(v < 0, v + 2^32, v)
for (seed in c(1, 42, 2026, 123456, 987654321)) for (j in 0:2) for (sj in 0:2) {
  RNGkind("L'Ecuyer-CMRG"); set.seed(seed)
  s <- .Random.seed
  for (k in seq_len(j)) s <- parallel::nextRNGStream(s)
  for (k in seq_len(sj)) s <- parallel::nextRNGSubStream(s)
  for (k in 1:6) add("state", c(seed, j, sj, k - 1), uns(s[k + 1]))
  assign(".Random.seed", s, envir = globalenv())
  u <- runif(6)
  for (i in 1:6) add("u", c(seed, j, sj, i - 1), u[i])
}
RNGkind("Mersenne-Twister")
emit("lecuyer", character(), list(cases))
