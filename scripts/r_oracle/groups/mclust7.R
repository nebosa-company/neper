# mclust, seventh part: mclustBootstrapLRT after set.seed.
# "boot" (id, model index (E 0 V 1 EII 2 VII 3 EEI 4 VEI 5 EVI 6 VVI 7 EEE 8 VVV 15), n, p, nboot, maxG (0 for NULL), seed, X[n p]); ids: 1 number of tested g,
# a bootstrap statistic depends on where the EM stops (tolerance 1e-5 on the log likelihood), so its checksum is compared at 1e-2; 100 + g the observed statistic, 200 + g the p value, 300 + g sum(b * boot[b, g])
suppressMessages(library(mclust))
cases <- list()
set.seed(20261205)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
add <- function(args, id, want, rel = 1e-6, abs = 1e-9) cases[[length(cases) + 1]] <<- case("boot", c(id, args), want, rel = rel, abs = abs)
one <- function(mi, n, p, nb, maxG) {
  cl <- sample(3, n, TRUE)
  X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.6, 1.5), each = n) + 2.4 * (cl - 1)
  sd <- sample(1:100000, 1)
  set.seed(sd)
  b <- tryCatch(suppressWarnings(mclustBootstrapLRT(X, modelName = tbl[mi + 1], nboot = nb, maxG = if (maxG > 0) maxG else NULL, verbose = FALSE)), error = function(e) NULL)
  if (is.null(b)) return(invisible(NULL))
  args <- c(mi, n, p, nb, maxG, sd, X)
  add(args, 1, length(b$G), rel = 0, abs = 0)
  for (g in b$G) { add(args, 100 + g, b$obs[g]); add(args, 200 + g, b$p.value[g], rel = 0, abs = 0); add(args, 300 + g, sum(seq_len(nb) * b$boot[, g]), rel = 1e-2, abs = 1e-6) }
}
for (mi in c(2, 3, 4, 5, 6, 7, 8, 15)) for (rep in 1:2) one(mi, sample(50:80, 1), 2, 12, if (rep == 1) 2 else 0)
for (mi in c(0, 1)) for (rep in 1:2) one(mi, sample(50:90, 1), 1, 12, if (rep == 1) 2 else 0)
emit("mclust7", "mclust", list(cases))
