# deSolve: the fixed-step methods euler and rk4 against e.math.ode.
#   args: (system, h, steps, y0...)   system 0 Lotka-Volterra, 1 Lorenz, 2 logistic, 3 harmonic oscillator; fn "euler" "rk4": the final state weighted by component
suppressMessages(library(deSolve))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
fs <- list(
  function(t, y, p) list(c(1.1 * y[1] - 0.4 * y[1] * y[2], 0.1 * y[1] * y[2] - 0.4 * y[2])),
  function(t, y, p) list(c(10 * (y[2] - y[1]), y[1] * (28 - y[3]) - y[2], y[1] * y[2] - 8 / 3 * y[3])),
  function(t, y, p) list(c(0.7 * y[1] * (1 - y[1] / 10))),
  function(t, y, p) list(c(y[2], -4 * y[1] - 0.2 * y[2])))
y0s <- list(c(10, 5), c(1, 1, 1), c(0.5), c(1, 0))
set.seed(20261224)
for (rep in 1:24) {
  sy <- (rep - 1) %% 4 + 1; h <- c(0.01, 0.02, 0.05, 0.1)[sample(1:4, 1)]; steps <- sample(5:60, 1)
  y0 <- y0s[[sy]] * runif(length(y0s[[sy]]), 0.8, 1.2); times <- seq(0, steps * h, length.out = steps + 1)
  for (m in c("euler", "rk4")) {
    out <- ode(y0, times, fs[[sy]], NULL, method = m)
    last <- out[nrow(out), -1]
    add(m, c(sy - 1, h, steps, y0), sum(last * seq_along(last)))
  }
}
emit("desolve", "deSolve", list(cases))
