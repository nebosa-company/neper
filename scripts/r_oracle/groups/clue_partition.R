# clue: Rand agreement and minimal Euclidean membership distance of hard partitions with classes 1..K (K the larger count).
# Args: (n, kx, ky, cx[n], cy[n], which): which 0 the Rand agreement, 1 the Euclidean dissimilarity.
suppressMessages(library(clue))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261240)
for (rep in 1:24) {
  n <- sample(8:40, 1); kx <- sample(2:4, 1); ky <- sample(2:4, 1)
  cx <- c(seq_len(kx), sample(seq_len(kx), n - kx, replace = TRUE))
  cy <- c(seq_len(ky), sample(seq_len(ky), n - ky, replace = TRUE))
  px <- as.cl_partition(factor(cx)); py <- as.cl_partition(factor(cy))
  base <- c(n, kx, ky, cx, cy)
  add("cl", c(base, 0), as.numeric(cl_agreement(px, py, method = "Rand")))
  add("cl", c(base, 1), as.numeric(cl_dissimilarity(px, py, method = "euclidean")))
}
# the other measures: kind 2 cRand, 3 NMI, 4 KP, 5 FM, 6 Jaccard, 7 purity, 8 PS, 9 VI, 10 comemberships, 11 symdiff, 12 manhattan (fn "cl", args as above with which = kind)
for (rep in 1:24) {
  n <- sample(10:45, 1); kx <- sample(2:5, 1); ky <- sample(2:5, 1)
  cx <- c(seq_len(kx), sample(seq_len(kx), n - kx, replace = TRUE))
  cy <- c(seq_len(ky), sample(seq_len(ky), n - ky, replace = TRUE))
  px <- as.cl_partition(factor(cx)); py <- as.cl_partition(factor(cy))
  base <- c(n, kx, ky, cx, cy)
  for (m in c("cRand", "NMI", "KP", "FM", "Jaccard", "purity", "PS")) add("cl", c(base, match(m, c("cRand", "NMI", "KP", "FM", "Jaccard", "purity", "PS")) + 1), as.numeric(cl_agreement(px, py, method = m)))
  for (m in c("VI", "comemberships", "symdiff", "manhattan")) add("cl", c(base, match(m, c("VI", "comemberships", "symdiff", "manhattan")) + 8), as.numeric(cl_dissimilarity(px, py, method = m)))
}
# the Gordon-Vichi and Boorman-Arabie dissimilarities: kind 13 GV1, 14 BA/A, 15 BA/C, 16 BA/E (BA/D is 1 - Rand)
for (rep in 1:24) {
  n <- sample(10:45, 1); kx <- sample(2:5, 1); ky <- sample(2:5, 1)
  cx <- c(seq_len(kx), sample(seq_len(kx), n - kx, replace = TRUE))
  cy <- c(seq_len(ky), sample(seq_len(ky), n - ky, replace = TRUE))
  px <- as.cl_partition(factor(cx)); py <- as.cl_partition(factor(cy))
  base <- c(n, kx, ky, cx, cy)
  for (m in c("GV1", "BA/A", "BA/C", "BA/E")) add("cl", c(base, match(m, c("GV1", "BA/A", "BA/C", "BA/E")) + 12), as.numeric(cl_dissimilarity(px, py, method = m)))
}
emit("clue_partition", "clue", list(cases))
