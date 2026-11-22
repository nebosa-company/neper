# vegan diversity, rarefy, Chao1 and vegdist on a sites-by-species count matrix.
#   args: (nr, nc, n_rarefy, counts[nr*nc] row-major)
#   fn "shannon" "simpson" "invsimpson" "pielou" "richness" "chao1" "rarefy" (per-site values weighted by position), "d_<method>" (lower triangle by column, weighted by position)
suppressMessages(library(vegan))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261220)
meths <- c("euclidean", "manhattan", "bray", "kulczynski", "canberra", "gower", "horn", "morisita", "jaccard")
for (rep in 1:20) {
  nr <- sample(4:10, 1); nc <- sample(5:14, 1)
  m <- matrix(rpois(nr * nc, sample(c(0.7, 2, 6), 1)), nr)
  for (i in seq_len(nr)) if (sum(m[i, ]) < 3) m[i, sample(nc, 3)] <- c(1, 2, 3)
  for (j in seq_len(nc)) if (sum(m[, j]) == 0) m[sample(nr, 1), j] <- 1
  nrf <- sample(2:max(2, min(rowSums(m)) - 1), 1)
  a <- c(nr, nc, nrf, as.vector(t(m)))
  add("shannon", a, ws(diversity(m, "shannon"))); add("simpson", a, ws(diversity(m, "simpson"))); add("invsimpson", a, ws(diversity(m, "invsimpson")))
  add("pielou", a, ws(diversity(m, "shannon") / log(specnumber(m)))); add("richness", a, ws(specnumber(m)))
  add("chao1", a, ws(estimateR(m)["S.chao1", ])); add("rarefy", a, ws(rarefy(m, nrf)))
  for (k in seq_along(meths)) add(paste0("d_", k - 1), a, ws(as.vector(vegdist(m, meths[k]))))
  add("d_9", a, ws(as.vector(vegdist(m, "jaccard", binary = TRUE))))
  # methods 10 to 12: altGower, cao and clark in vegan's own vocabulary
  add("d_10", a, ws(as.vector(vegdist(m, "altGower"))))
  add("d_11", a, ws(as.vector(vegdist(m, "cao"))))
  add("d_12", a, ws(as.vector(vegdist(m, "clark"))))
  add("d_13", a, ws(as.vector(vegdist(m, "chao"))))
  add("d_14", a, ws(as.vector(vegdist(m, "raup"))))
}
emit("vegan", "vegan", list(cases))
