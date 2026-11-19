# mstate: msprep(time, status, trans = tmat) on a four-state acyclic model (1 to 2 or 3, 2 to 3 or 4, 3 to 4). Args: (K, n, i, c, trans[K * K] row-major with 0 for no
# transition, time[n * K] row-major with -1 for the starting state, status[n * K]): the value at row i (0-based; -1 asks for the row count) and column c (0-based, 0..6 id from to trans Tstart Tstop status).
.libPaths(c(Sys.getenv("R_ORACLE_LIB"), .libPaths())); suppressMessages(library(mstate))
cases <- list()
set.seed(20262313)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ms", args, want, rel = 1e-12, abs = 1e-12)
tm <- transMat(x = list(c(2, 3), c(3, 4), c(4), c()), names = c("a", "b", "c", "d")); K <- 4
tflat <- as.vector(t(ifelse(is.na(tm), 0, tm)))
for (rep in 1:4) {
  n <- sample(8:20, 1)
  t2 <- round(runif(n, 0.1, 5), 3); t3 <- round(runif(n, 0.1, 5), 3); t4 <- round(pmax(t2, t3) + runif(n, 0.1, 3), 3)
  tm4 <- cbind(NA, t2, t3, t4); st <- cbind(NA, rbinom(n, 1, 0.7), rbinom(n, 1, 0.7), rbinom(n, 1, 0.8))
  d <- msprep(time = tm4, status = st, trans = tm)
  tim <- tm4; tim[is.na(tim)] <- -1; sts <- st; sts[is.na(sts)] <- 0
  args <- function(i, c) c(K, n, i, c, tflat, as.vector(t(tim)), as.vector(t(sts)))
  add(args(-1, 0), nrow(d))
  m <- as.matrix(d[, c("id", "from", "to", "trans", "Tstart", "Tstop", "status")])
  for (i in seq(0, nrow(d) - 1, by = 3)) for (c in 0:6) add(args(i, c), m[i + 1, c + 1])
}
emit("mstate_msprep", "mstate", list(cases))
