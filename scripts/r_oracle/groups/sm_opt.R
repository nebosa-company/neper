# sm: the sm.options() defaults (one case per number, logical or string entry, input = the option name; "optv" args (k) the vector defaults),
# the residual scale sm.regression reports ("hsig" (n, x[n], y[n])) and its model.y at one point ("hmy" (n, kind 0 no.effect 1 linear, p, x[n], y[n])).
suppressMessages(library(sm))
cases <- list()
o <- sm.options()
for (nm in names(o)) {
  v <- o[[nm]]
  if (is.function(v) || is.null(v) || nm == "col.palette") next
  if (is.character(v) && length(v) == 1) cases[[length(cases) + 1]] <- case("optt", numeric(0), v, input = nm)
  else if (length(v) == 1) cases[[length(cases) + 1]] <- case("opts", numeric(0), as.numeric(v), rel = 0, abs = 0, input = nm)
  else for (k in 0:4) cases[[length(cases) + 1]] <- case("optv", k, if (k < length(v)) as.numeric(v[k + 1]) else NA_real_, rel = 0, abs = 0, input = nm)
}
set.seed(20262511)
for (rep in 1:30) {
  n <- sample(15:80, 1); x <- runif(n, 0, 10); y <- sin(x) + rnorm(n, 0, 0.3)
  r <- sm.regression(x, y, h = 1, display = "none", eval.points = 5)
  cases[[length(cases) + 1]] <- case("hsig", c(n, x, y), r$sigma, rel = 1e-11, abs = 1e-13)
  p <- runif(1, 1, 9)
  for (kd in 0:1) {
    m <- sm.regression(x, y, h = 1, model = c("no.effect", "linear")[kd + 1], display = "none", eval.points = p, verbose = 0)
    cases[[length(cases) + 1]] <- case("hmy", c(n, kd, p, x, y), m$model.y[1], rel = 1e-11, abs = 1e-13)
  }
}
emit("sm_opt", "sm", list(cases))
