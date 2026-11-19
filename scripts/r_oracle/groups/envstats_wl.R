# EnvStats: eweibull (mle) and elnorm (mvue, mle). Args: (fam 0 eweibull 1 elnorm mvue 2 elnorm mle, what 0 first parameter 1 second, x[n]).
suppressMessages(library(EnvStats))
cases <- list()
set.seed(20262336)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("wl", args, want, rel = 1e-5, abs = 1e-8)
for (rep in 1:30) {
  n <- sample(15:60, 1); fam <- (rep - 1) %% 3
  x <- if (fam == 0) rweibull(n, runif(1, 0.8, 4), runif(1, 0.5, 5)) else rlnorm(n, runif(1, -1, 2), runif(1, 0.3, 1.2))
  e <- if (fam == 0) eweibull(x) else elnorm(x, method = if (fam == 1) "mvue" else "mle"); p <- unname(e$parameters)
  add(c(fam, 0, x), p[1]); add(c(fam, 1, x), p[2])
}
emit("envstats_wl", "EnvStats", list(cases))
