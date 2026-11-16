# rngtools::RNGseq(n, seed): stream i (0-based) of the sequence, word k of the state (unsigned).
#   fn "seq": (seed, i, k) numeric scalar seed while the generator is the Mersenne-Twister; "seqc" the same while the current generator is L'Ecuyer-CMRG (set.seed(seed, kind = CMRG) directly); "seq6": (s1..s6, i, k) a 6-long seed given directly
suppressMessages(library(rngtools))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
uns <- function(v) ifelse(v < 0, v + 2^32, v)
for (seed in c(1, 42, 123, 2026, 987654)) {
  RNGkind("Mersenne-Twister"); set.seed(5)
  s <- RNGseq(4, seed)
  for (i in 1:4) for (k in 1:6) add("seq", c(seed, i - 1, k - 1), uns(s[[i]][k + 1]))
  RNGkind("L'Ecuyer-CMRG"); set.seed(5)
  s <- RNGseq(4, seed)
  for (i in 1:4) for (k in 1:6) add("seqc", c(seed, i - 1, k - 1), uns(s[[i]][k + 1]))
}
RNGkind("Mersenne-Twister")
for (rep in 1:5) {
  sd6 <- as.integer(sample(1:4294944442, 6) - 2147483648)
  s <- RNGseq(3, sd6)
  for (i in 1:3) for (k in 1:6) add("seq6", c(sd6, i - 1, k - 1), uns(s[[i]][k + 1]))
}
emit("rngseq", "rngtools", list(cases))
