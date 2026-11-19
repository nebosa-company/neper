# EnvStats: egamma (mle, bcmle, mme). Args: (method 0 mle 1 bcmle 2 mme, what 0 shape 1 scale, x[n]).
suppressMessages(library(EnvStats))
cases <- list()
set.seed(20262335)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("eg", args, want, rel = 1e-5, abs = 1e-8)
for (rep in 1:30) {
  n <- sample(15:60, 1); x <- rgamma(n, runif(1, 0.8, 5), runif(1, 0.2, 2)); m <- (rep - 1) %% 3
  e <- egamma(x, method = c("mle", "bcmle", "mme")[m + 1]); p <- unname(e$parameters)
  add(c(m, 0, x), p[1]); add(c(m, 1, x), p[2])
}
emit("envstats_gamma", "EnvStats", list(cases))
