# mstate: msfit(coxph(Surv(Tstart, Tstop, status) ~ strata(trans), method = "breslow"), trans = tmat) on msprep data of a four-state model. Args: (K, n, i, c, trans[K * K], time[n * K]
# (-1 for the starting state), status[n * K]): c = 0 the unique-time count (i ignored), c = 1 time i, c = 2 + k the cumulative hazard of transition k (0-based) at time i.
.libPaths(c(Sys.getenv("R_ORACLE_LIB"), .libPaths())); suppressMessages(library(mstate))
cases <- list()
set.seed(20262314)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("mf", args, want, rel = 1e-10, abs = 1e-12)
tm <- transMat(x = list(c(2, 3), c(3, 4), c(4), c()), names = c("a", "b", "c", "d")); K <- 4
tflat <- as.vector(t(ifelse(is.na(tm), 0, tm)))
for (rep in 1:5) {
  n <- sample(15:40, 1)
  t2 <- round(runif(n, 0.1, 5), 3); t3 <- round(runif(n, 0.1, 5), 3); t4 <- round(pmax(t2, t3) + runif(n, 0.1, 3), 3)
  tm4 <- cbind(NA, t2, t3, t4); st <- cbind(NA, rbinom(n, 1, 0.7), rbinom(n, 1, 0.7), rbinom(n, 1, 0.8))
  d <- suppressWarnings(msprep(time = tm4, status = st, trans = tm))
  mf <- msfit(coxph(Surv(Tstart, Tstop, status) ~ strata(trans), data = d, method = "breslow"), trans = tm)
  tim <- tm4; tim[is.na(tim)] <- -1; sts <- st; sts[is.na(sts)] <- 0
  args <- function(i, c) c(K, n, i, c, tflat, as.vector(t(tim)), as.vector(t(sts)))
  H <- mf$Haz; ut <- sort(unique(H$time)); add(args(0, 0), length(ut))
  for (i in seq_along(ut)) { add(args(i - 1, 1), ut[i]); for (k in 1:5) add(args(i - 1, 1 + k), H$Haz[H$trans == k & H$time == ut[i]]) }
}
emit("mstate_msfit", "mstate", list(cases))
