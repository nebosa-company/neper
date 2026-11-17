# sn: dsn (with tau), psn through T.Owen, qsn (tau = 0, solver NR) and dst.
#   args: (xi, omega, alpha, tau_or_nu, v)   fn "dsn" "psn" "qsn" "dst"
suppressMessages(library(sn))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10)
set.seed(20261203)
for (rep in 1:12) {
  xi <- runif(1, -1, 1); om <- runif(1, 0.5, 2.5); al <- c(runif(1, -6, 6), runif(1, 0.1, 3), runif(1, -3, -0.1), 12)[(rep - 1) %% 4 + 1]
  xs <- xi + om * c(-1.4, -0.4, 0.2, 0.9, 1.7, 2.6)
  tau <- c(0, 0.7, -0.5)[(rep - 1) %% 3 + 1]
  for (x in xs) add("dsn", c(xi, om, al, tau, x), dsn(x, xi, om, al, tau))
  pp <- xi + om * c(0.2, 0.5, 0.8, 1.1, 1.6, 2.2)
  if (all((pp - xi) / om * al > -5)) for (x in pp) add("psn", c(xi, om, al, 0, x), psn(c(pp), xi, om, al)[match(x, pp)])
  for (p in c(0.02, 0.2, 0.5, 0.8, 0.97)) add("qsn", c(xi, om, al, 0, p), qsn(p, xi, om, al), rel = 1e-6)
  nu <- c(2.5, 4, 7, 15)[(rep - 1) %% 4 + 1]
  for (x in xs) add("dst", c(xi, om, al, nu, x), dst(x, xi, om, al, nu))
}
# rsn (tau = 0 and tau != 0) and rst after set.seed: args (xi, omega, alpha, tau or nu, n, seed, index)
for (rep in 1:20) {
  xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 0, 1, 4)[sample(5, 1)]; n <- sample(5:25, 1); sd <- sample(1:100000, 1)
  tau <- if (rep %% 3 == 0) c(-0.5, 0.7, 1.5)[sample(3, 1)] else 0
  set.seed(sd); r <- as.numeric(rsn(n, xi, om, al, tau)); for (k in seq_len(n)) add("rsn", c(xi, om, al, tau, n, sd, k - 1), r[k])
  nu <- c(3, 7.5, 30, Inf)[sample(4, 1)]
  set.seed(sd); r2 <- as.numeric(rst(n, xi, om, al, nu)); for (k in seq_len(n)) add("rst", c(xi, om, al, nu, n, sd, k - 1), r2[k])
}
# st.cumulants "cum" (xi, omega, alpha, nu, k)
for (rep in 1:20) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 0, 1, 4)[sample(5, 1)]; nu <- c(5.5, 7, 12, 40, Inf)[(rep - 1) %% 5 + 1]
  cm <- st.cumulants(xi, om, al, nu); for (k in 1:4) add("cum", c(xi, om, al, nu, k), unname(cm[k])) }
emit("sn", "sn", list(cases))
