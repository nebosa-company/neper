# R's rgamma for a >= 1 and rchisq: draws under set.seed, compared one by one. Args: (kind 0 rgamma 1 rchisq, a_or_df, scale, seed, count): the sum of the draws weighted by position.
cases <- list()
set.seed(20262348)
for (rep in 1:60) {
  kind <- rep %% 2; a <- if (rep %% 3 == 0) runif(1, 1, 3) else if (rep %% 3 == 1) runif(1, 3.7, 12) else runif(1, 14, 90); sc <- runif(1, 0.5, 3); sd <- sample(1:100000, 1); m <- 12
  set.seed(sd); v <- if (kind == 0) rgamma(m, a, scale = sc) else rchisq(m, 2 * a)
  cases[[length(cases) + 1]] <- case("rg", c(kind, if (kind == 0) a else 2 * a, sc, sd, m), sum(v * seq_len(m)), rel = 1e-12, abs = 1e-12)
}
emit("rgamma", "base", list(cases))
