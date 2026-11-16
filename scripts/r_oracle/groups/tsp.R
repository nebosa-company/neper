# TSP: tour constructions, 2-opt, tour length, ATSP reformulation, cut_tour.
#   args: (kind, q, seed, n, p, matrix row-major n*n)
#   kind 0 nn(start p) 1 repetitive_nn 2 insertion(type p 0..3, start = seed %% n + 1; set.seed(seed) first) 3 two_opt from sample(n) under set.seed(seed)
#        4 ATSP reformulation (q 0 sum, 1 position-weighted sum) 5 cut_tour(tour appended after the matrix, cut city p, exclude q)
#   q for kinds 0..3: 0 sum((pos) * city) of the 1-based tour, 1 its length; kind 5 q = exclude flag, answer sum(pos * city) of the path
suppressMessages(library(TSP))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("tsp", args, want, rel = 1e-9, abs = 1e-9)
chk <- function(t) sum(seq_along(t) * as.integer(t))
set.seed(20261117)
for (rep in 1:40) {
  n <- sample(6:25, 1); pts <- matrix(runif(2 * n), n, 2); dm <- as.matrix(dist(pts)); x <- TSP(dm); mrow <- as.vector(t(dm))
  p <- sample(n, 1); tn <- TSP:::tsp_nn(x, control = list(start = p))
  add(c(0, 0, 0, n, p, mrow), chk(tn)); add(c(0, 1, 0, n, p, mrow), tour_length(x, tn))
  tr <- TSP:::tsp_repetitive_nn(x, list())
  add(c(1, 0, 0, n, 0, mrow), chk(tr)); add(c(1, 1, 0, n, 0, mrow), tour_length(x, tr))
  for (ty in 0:3) {
    seed <- sample(1e6, 1); st <- seed %% n + 1; set.seed(seed)
    ti <- TSP:::tsp_insertion(x, c("nearest", "farthest", "cheapest", "arbitrary")[ty + 1], control = list(start = st))
    add(c(2, 0, seed, n, ty, mrow), chk(ti)); add(c(2, 1, seed, n, ty, mrow), tour_length(x, ti))
  }
  seed <- sample(1e6, 1); set.seed(seed); to <- TSP:::tsp_two_opt(x, list())
  add(c(3, 0, seed, n, 0, mrow), chk(to)); add(c(3, 1, seed, n, 0, mrow), tour_length(x, to))
  am <- matrix(round(runif(n * n, 1, 100), 2), n, n); diag(am) <- 0
  rf <- as.matrix(reformulate_ATSP_as_TSP(ATSP(am), infeasible = 500, cheap = -500))
  add(c(4, 0, 0, n, 0, as.vector(t(am))), sum(rf)); add(c(4, 1, 0, n, 0, as.vector(t(am))), sum(outer(seq_len(2 * n), seq_len(2 * n)) * rf))
  cc <- sample(n, 1)
  for (ex in 0:1) add(c(5, ex, 0, n, cc, mrow, as.integer(tn)), chk(cut_tour(TOUR(as.integer(tn)), cc, exclude_cut = ex == 1)))
}
emit("tsp", "TSP", list(cases))
