# cluster::mona against e.algo.stat.clustermona: binary data of arbitrary two-valued columns, missing values and the five
# error returns.
#   args: (n, p, data)   data is x row-major, NA as -999999
#   fn names the answer: jerr (0, or the package's error: 1 object all missing, 2 variable half missing, 3 variable constant,
#     4 every variable has a missing value, 5 fewer than two variables), then position-weighted sums of order, step (nban[-1]),
#     variable (lava[-1]) and data (the recoded 0/1 matrix with the missing values filled, row-major)
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 0, abs = 0) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270106)

onemona <- function(x) {
  n <- nrow(x); p <- ncol(x)
  a <- c(n, p, as.vector(t(ifelse(is.na(x), -999999, x))))
  msgs <- c("an object was found with all values missing", "more than half values missing", "all non missing values identical",
            "all variables have at least one missing value", "needs at least p >= 2")
  r <- tryCatch(mona(x), error = function(e) conditionMessage(e))
  if (is.character(r)) {
    code <- which(vapply(msgs, function(m) grepl(m, r, fixed = TRUE), NA))
    if (length(code) == 1) add("jerr", a, code)
    return(invisible())
  }
  add("jerr", a, 0)
  add("order", a, wsum(r$order)); add("step", a, wsum(r$step)); add("variable", a, wsum(as.integer(r$variable)))
  add("data", a, wsum(as.vector(t(r$data))))
}

gen <- function(n, p, na = 0, density = 0.4) {
  z <- rbinom(n, 1, 0.5); w <- rbinom(n, 1, 0.5)
  x <- matrix(0, n, p)
  for (j in 1:p) {
    base <- if (j %% 3 == 0) w else z
    flip <- rbinom(n, 1, runif(1, 0.05, 0.45))
    x[, j] <- abs(base - flip)
  }
  # arbitrary two-valued labels per column
  lab <- cbind(sample(0:9, p, replace = TRUE), sample(10:19, p, replace = TRUE))
  for (j in 1:p) x[, j] <- ifelse(x[, j] == 1, lab[j, 2], lab[j, 1])
  if (na > 0) x[sample(n * p, na)] <- NA
  x
}

for (rep in 1:30) onemona(gen(sample(6:50, 1), sample(2:9, 1)))
for (rep in 1:25) onemona(gen(sample(10:50, 1), sample(3:9, 1), na = sample(1:10, 1)))
# the error returns
x <- gen(12, 4); x[3, ] <- NA; onemona(x)
x <- gen(20, 4); x[1:11, 2] <- NA; onemona(x)
x <- gen(20, 4, na = 3); x[, 1] <- NA; x[1, 1] <- 1; x[2, 1] <- 1; x[3:4, 1] <- 1; onemona(x)
x <- gen(14, 3); x[1, 1] <- NA; x[2, 2] <- NA; x[3, 3] <- NA; onemona(x)
onemona(gen(10, 1))
emit("clustermona", "cluster", list(cases))
