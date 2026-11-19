# mstate: probtrans(msfit, predt, direction = "fixedhorizon", variance = FALSE). The msfit is built by hand (probtrans reads only $Haz and $trans). Args: (S, nt, nT, predt, i, j, k, from[nt], to[nt],
# times[nT], cum[nt * nT] trans-major): the pstate of start state j (0-based) in state k at the i-th row of the result (row 0 the product over all times up to predt, the last row the identity at predt).
.libPaths(c(Sys.getenv("R_ORACLE_LIB"), .libPaths())); suppressMessages(library(mstate))
cases <- list()
set.seed(20262312)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pf", args, want, rel = 1e-10, abs = 1e-12)
for (rep in 1:6) {
  tm <- transMat(x = list(c(2, 3), c(3, 4), c(4), c()), names = c("a", "b", "c", "d"))
  tr <- mstate:::to.trans2(tm); nt <- nrow(tr); S <- 4
  nT <- sample(6:12, 1); times <- sort(round(runif(nT, 0.1, 5), 3)); times <- unique(times); nT <- length(times)
  cum <- t(apply(matrix(runif(nt * nT, 0, 0.12), nt, nT), 1, cumsum))
  Haz <- data.frame(time = rep(times, nt), Haz = as.vector(t(cum)), trans = rep(1:nt, each = nT))
  obj <- structure(list(Haz = Haz, varHaz = NULL, trans = tm), class = "msfit")
  predt <- if (rep %% 2 == 0) times[nT - 1] else times[nT - 1] + 0.01
  pt <- probtrans(obj, predt, direction = "fixedhorizon", variance = FALSE)
  for (j in 1:S) {
    ps <- as.matrix(pt[[j]][, 2:(S + 1)])
    for (i in seq(0, nrow(ps) - 1, by = 2)) for (k in 1:S)
      add(c(S, nt, nT, predt, i, j - 1, k - 1, tr$from - 1, tr$to - 1, times, as.vector(t(cum))), ps[i + 1, k])
  }
}
emit("mstate_fixed", "mstate", list(cases))
