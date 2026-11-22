# uwot::umap with exact neighbours (FNN), given a and b. "um": args (seed, n, d, k, nd, n_epochs, alpha, a, b, gamma, negative_sample_rate, set_op_mix_ratio, local_connectivity, init (0 random, 1 spectral),
# x[n*d] row-major, sel); the embedding is row-major, sel >= 0 one coordinate, -1 the sum of squares, -2 the sum of coordinate * (1-based position).
# Tolerance: the optimizer runs in single precision, so a last-bit libm difference that flips one float rounding moves a coordinate by about 1e-7; cases are kept short.
# When a is negative the fit goes through find_ab_params: spread = -a and min_dist = b.
suppressMessages(library(uwot))
cases <- list()
sels <- function(nn) c(0, floor(nn / 2), nn - 1, -1, -2)
pick <- function(v, s) if (s >= 0) v[s + 1] else if (s == -1) sum(v^2) else sum(v * seq_along(v))
emitcases <- function(pre, v, post, rel = 1e-9, abs = 1e-10) {
  for (s in sels(length(v))) cases[[length(cases) + 1]] <<- case("um", c(pre, post, s), pick(v, s), rel = rel, abs = abs)
}
set.seed(20262300)
for (rep in 1:12) {
  n <- sample(30:60, 1); nd <- c(2, 2, 3)[1 + rep %% 3]; d <- sample(max(nd, 2):6, 1); k <- sample(8:14, 1)
  centers <- matrix(rnorm(3 * d) * 1, 3, d)
  X <- centers[sample(1:3, n, replace = TRUE), , drop = FALSE] + matrix(round(rnorm(n * d), 3), n, d)
  ne <- sample(c(20, 40, 60), 1); alpha <- c(1, 0.5, 1.5)[1 + rep %% 3]; md <- c(0.01, 0.1, 0.3)[1 + rep %% 3]; sp <- c(1, 1.5, 1)[1 + rep %% 3]
  ab <- uwot:::find_ab_params(spread = sp, min_dist = md); viaab <- rep %% 3 == 0
  gam <- c(1, 0.7)[1 + rep %% 2]; nsr <- c(5, 3, 7)[1 + rep %% 3]; mix <- c(1, 0.5, 0.8, 1)[1 + rep %% 4]; lc <- c(1, 1, 1.5)[1 + rep %% 3]
  init <- rep %% 2; sd0 <- sample(1:100000, 1)
  r <- umap(X, n_neighbors = k, n_components = nd, n_epochs = ne, learning_rate = alpha, a = if (viaab) NULL else ab[1], b = if (viaab) NULL else ab[2], min_dist = md, spread = sp, repulsion_strength = gam,
            negative_sample_rate = nsr, set_op_mix_ratio = mix, local_connectivity = lc, init = c("random", "spectral")[1 + init],
            seed = sd0, n_sgd_threads = 0, n_threads = 1, verbose = FALSE, nn_method = "fnn")
  emitcases(c(sd0, n, d, k, nd, ne, alpha, if (viaab) -sp else ab[1], if (viaab) md else ab[2], gam, nsr, mix, lc, init, as.vector(t(X))), as.vector(t(r)), NULL)
}
emit("uwot", "uwot", list(cases))
