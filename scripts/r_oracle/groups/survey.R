# survey svymean, svytotal and svyratio on a stratified cluster sample (PSU ids unique across strata), with and without fpc.
#   args: (n, H, P, y[n], x[n], w[n], strata[n] 0-based, psu[n] 0-based, fpc[H] PSU population per stratum or 0)
#   fn "mean" "semean" "total" "setotal" "ratio" "seratio"
suppressMessages(library(survey))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261219)
for (rep in 1:24) {
  H <- sample(2:5, 1); nps <- sample(2:6, H, TRUE); P <- sum(nps); use_fpc <- rep %% 2
  psu <- rep(seq_len(P), sample(2:6, P, TRUE)); n <- length(psu); st <- rep(seq_len(H), nps)[psu]
  y <- rnorm(n, 5) + psu * 0.1; x <- runif(n, 1, 3) + y * 0.2; w <- runif(n, 1, 5)
  Nh <- if (use_fpc) nps + sample(1:20, H, TRUE) else rep(0, H)
  d <- data.frame(y, x, w, st, psu, fp = Nh[st])
  des <- if (use_fpc) svydesign(ids = ~psu, strata = ~st, weights = ~w, fpc = ~fp, data = d) else svydesign(ids = ~psu, strata = ~st, weights = ~w, data = d)
  a <- c(n, H, P, y, x, w, st - 1, psu - 1, Nh)
  m <- svymean(~y, des); t <- svytotal(~y, des); r <- svyratio(~y, ~x, des)
  add("mean", a, as.numeric(coef(m))); add("semean", a, as.numeric(SE(m)))
  add("total", a, as.numeric(coef(t))); add("setotal", a, as.numeric(SE(t)))
  add("ratio", a, as.numeric(coef(r))); add("seratio", a, as.numeric(SE(r)))
}
emit("survey", "survey", list(cases))
