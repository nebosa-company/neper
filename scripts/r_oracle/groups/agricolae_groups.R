# agricolae grouping letters (LSD, HSD, SNK and Duncan with group = TRUE) and kruskal with its post-hoc comparisons. Balanced designs.
#   args: (kind, n, k, y[n], group labels 1..k [n]); kind 0 LSD, 1 HSD, 3 SNK, 4 Duncan (fn "g": the letter bit mask of the treatment at sorted position idx is
#   hdr(.., idx)), 5 kruskal (fn "kw": want H, p.chisq, then the weighted sums of the comparisons' difference, p value, lower and upper limit)
suppressMessages(library(agricolae))
cases <- list()
set.seed(20261901)
letrs <- c(letters[1:26], LETTERS[1:26])
mask <- function(s) sum(2^(match(strsplit(s, "")[[1]], letrs) - 1))
for (rep in 1:14) {
  k <- sample(4:7, 1); sz <- sample(4:8, 1); n <- k * sz
  g <- factor(rep(1:k, each = sz)); y <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), 4)
  m <- aov(y ~ g)
  for (kind in c(0, 1, 3, 4)) {
    r <- switch(match(kind, c(0, 1, 3, 4)), LSD.test(m, "g", p.adj = "none"), HSD.test(m, "g"), SNK.test(m, "g"), duncan.test(m, "g"))$groups
    a <- c(kind, n, k, y, as.numeric(g))
    for (i in seq_len(nrow(r))) {
      cases[[length(cases) + 1]] <- case("g", c(a, i - 1), mask(as.character(r$groups[i])), rel = 0, abs = 0)
      cases[[length(cases) + 1]] <- case("gt", c(a, i - 1), as.numeric(rownames(r)[i]), rel = 0, abs = 0)
    }
  }
  kr <- kruskal(y, g, group = FALSE)
  cmp <- kr$comparison; w <- seq_len(nrow(cmp)); a <- c(5, n, k, y, as.numeric(g))
  add <- function(fn, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = rel, abs = abs)
  add("kh", kr$statistics$Chisq); add("kp", kr$statistics$p.chisq)
  add("kd", sum(cmp[[1]] * w)); add("kpv", sum(cmp[[2]] * w), abs = 1e-4 * nrow(cmp) * (nrow(cmp) + 1) / 2)
  add("kl", sum(cmp$LCL * w)); add("ku", sum(cmp$UCL * w))
}
# friedman (kind 6): args (6, nb, nt, y[nb nt] row-major); fn "fc" Chisq, "fp" p.chisq, "ff" F, "fpf" p.F, "fd" "fq" "fl" "fu" the weighted sums over the pairs of the difference, p value and limits
for (rep in 1:10) {
  nb <- sample(5:12, 1); nt <- sample(3:6, 1)
  y <- matrix(round(rnorm(nb * nt) + rep(seq_len(nt) * runif(1, 0, 0.5), each = nb), if (rep %% 2 == 0) 1 else 4), nb, nt)
  d <- data.frame(judge = factor(rep(seq_len(nb), nt)), trt = factor(rep(seq_len(nt), each = nb)), ev = as.vector(y))
  fr <- friedman(d$judge, d$trt, d$ev, group = FALSE)
  cmp <- fr$comparison; w <- seq_len(nrow(cmp)); a <- c(6, nb, nt, as.vector(t(y)))
  add <- function(fn, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = rel, abs = abs)
  add("fc", fr$statistics$Chisq); add("fp", fr$statistics$p.chisq); add("ff", fr$statistics$F); add("fpf", fr$statistics$p.F)
  add("fd", sum(cmp[[1]] * w)); add("fq", sum(cmp[[2]] * w), abs = 1e-4 * nrow(cmp) * (nrow(cmp) + 1) / 2)
  add("fl", sum(cmp$LCL * w), abs = 0.01 * nrow(cmp) * (nrow(cmp) + 1) / 2 + 1e-9); add("fu", sum(cmp$UCL * w), abs = 0.01 * nrow(cmp) * (nrow(cmp) + 1) / 2 + 1e-9)
}
# waller.test (kind 7, K = 100, any sizes): args (7, n, k, y[n], group labels [n], idx); fn "wt" the critical value, "wf" the F value, "wm" the sum over pairs of MSD weighted by pair
# position, "wg" the group letter mask at sorted position idx, "wo" the treatment at that position
for (rep in 1:8) {
  k <- sample(3:6, 1); sz <- if (rep %% 2 == 0) rep(sample(4:7, 1), k) else sample(3:8, k, replace = TRUE); n <- sum(sz)
  g <- factor(rep(1:k, sz)); y <- round(rnorm(n) + as.numeric(g) * runif(1, 0.1, 0.9), 4)
  m <- aov(y ~ g)
  wt <- tryCatch(waller.test(m, "g", group = TRUE), error = function(e) NULL)
  if (is.null(wt)) next
  cmp <- waller.test(m, "g", group = FALSE)$comparison
  a <- c(7, n, k, y, as.numeric(g))
  add <- function(fn, extra, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, c(a, extra), want, rel = rel, abs = abs)
  tw <- if ("Waller" %in% names(wt$statistics)) wt$statistics$Waller else cmp$MSD[1] / sqrt(wt$statistics$MSerror * (1 / sz[1] + 1 / sz[2])); add("wt", 0, tw, rel = 0, abs = 1e-9); add("wf", 0, wt$statistics$F.Value)
  if ("MSD" %in% names(cmp)) add("wm", 0, sum(cmp$MSD * seq_len(nrow(cmp)))) else add("wm", 0, wt$statistics$CriticalDifference * sum(seq_len(nrow(cmp))))
  r <- wt$groups
  for (i in seq_len(nrow(r))) { add("wg", i - 1, mask(as.character(r$groups[i])), rel = 0, abs = 0); add("wo", i - 1, as.numeric(rownames(r)[i]), rel = 0, abs = 0) }
}
# randomised designs under set.seed(seed, "Mersenne-Twister"): kind 8 design.crd args (8, seed, t, idx, reps[t]) fn "dt" the treatment code (0-based) and "dr" the replicate number of plot idx;
# kind 9 design.rcbd args (9, seed, t, blocks, first, idx) fn "bt" the treatment code of plot idx
for (rep in 1:8) {
  tn <- sample(3:7, 1); reps <- sample(2:5, tn, replace = TRUE); seed <- 500 + rep
  trt <- letters[1:tn]
  d <- design.crd(trt, reps, serie = 2, seed = seed, kinds = "Mersenne-Twister")$book
  for (i in seq_len(nrow(d))) {
    cases[[length(cases) + 1]] <- case("dt", c(8, seed, tn, i - 1, reps), match(as.character(d[[3]][i]), trt) - 1, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("dr", c(8, seed, tn, i - 1, reps), d$r[i], rel = 0, abs = 0)
  }
  nbk <- sample(2:5, 1); fst <- rep %% 2 == 0
  b <- design.rcbd(trt, nbk, serie = 2, seed = seed, kinds = "Mersenne-Twister", first = fst)$book
  for (i in seq_len(nrow(b))) cases[[length(cases) + 1]] <- case("bt", c(9, seed, tn, nbk, as.numeric(fst), i - 1), match(as.character(b[[3]][i]), trt) - 1, rel = 0, abs = 0)
}
# the package's default Super-Duper generator: kind 10 design.crd args (10, seed, t, idx, reps[t]) fn "dst" and "dsr"; kind 11 design.rcbd args (11, seed, t, blocks, first, idx) fn "bst"
for (rep in 1:6) {
  tn <- sample(3:7, 1); reps <- sample(2:5, tn, replace = TRUE); seed <- 700 + rep
  trt <- letters[1:tn]
  d <- design.crd(trt, reps, serie = 2, seed = seed)$book
  for (i in seq_len(nrow(d))) {
    cases[[length(cases) + 1]] <- case("dst", c(10, seed, tn, i - 1, reps), match(as.character(d[[3]][i]), trt) - 1, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("dsr", c(10, seed, tn, i - 1, reps), d$r[i], rel = 0, abs = 0)
  }
  nbk <- sample(2:5, 1); fst <- rep %% 2 == 0
  b <- design.rcbd(trt, nbk, serie = 2, seed = seed, first = fst)$book
  for (i in seq_len(nrow(b))) cases[[length(cases) + 1]] <- case("bst", c(11, seed, tn, nbk, as.numeric(fst), i - 1), match(as.character(b[[3]][i]), trt) - 1, rel = 0, abs = 0)
}
# design.lsd and design.split, Mersenne-Twister (sd 0) and the default Super-Duper (sd 1) streams. op 12 design.lsd (12, seed, sd, r, first, idx) fn "ls" the treatment code at plot idx;
# op 13 split over an rcbd (13, seed, sd, n1, blocks, n2, first, idx) fn "s1" whole-plot treatment, "s2" subplot treatment at book row idx; op 14 split over an lsd (14, seed, sd, r, n2, first, idx) fn "t1" "t2"
kk <- function(sd) if (sd == 1) "Super-Duper" else "Mersenne-Twister"
for (rep in 1:8) {
  sd <- rep %% 2; seed <- 800 + rep; r <- sample(3:6, 1); trt <- letters[1:r]; fst <- rep %% 4 < 2
  b <- design.lsd(trt, serie = 2, seed = seed, kinds = kk(sd), first = fst)$book
  for (i in seq_len(nrow(b))) cases[[length(cases) + 1]] <- case("ls", c(12, seed, sd, r, as.numeric(fst), i - 1), match(as.character(b[[4]][i]), trt) - 1, rel = 0, abs = 0)
  n1 <- sample(3:4, 1); nb <- sample(2:3, 1); n2 <- sample(2:4, 1)
  t1 <- letters[1:n1]; t2 <- LETTERS[1:n2]
  bk <- design.split(t1, t2, r = nb, design = "rcbd", serie = 2, seed = seed, kinds = kk(sd), first = fst)$book
  for (i in seq_len(nrow(bk))) {
    cases[[length(cases) + 1]] <- case("s1", c(13, seed, sd, n1, nb, n2, as.numeric(fst), i - 1), match(as.character(bk[[4]][i]), t1) - 1, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("s2", c(13, seed, sd, n1, nb, n2, as.numeric(fst), i - 1), match(as.character(bk[[5]][i]), t2) - 1, rel = 0, abs = 0)
  }
  bl <- design.split(t1, t2, design = "lsd", serie = 2, seed = seed, kinds = kk(sd), first = fst)$book
  for (i in seq_len(nrow(bl))) {
    cases[[length(cases) + 1]] <- case("t1", c(14, seed, sd, n1, n2, as.numeric(fst), i - 1), match(as.character(bl[[5]][i]), t1) - 1, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("t2", c(14, seed, sd, n1, n2, as.numeric(fst), i - 1), match(as.character(bl[[6]][i]), t2) - 1, rel = 0, abs = 0)
  }
}
# design.bib: op 15 (15, seed, sd, v, k, idx) fn "bb" the treatment code at plot idx (r from the package's search)
invisible(capture.output(suppressMessages({
  for (cfg in list(c(7, 3), c(6, 3), c(5, 4), c(4, 2), c(7, 4))) for (sd in 0:1) {
    v <- cfg[1]; k <- cfg[2]; seed <- 900 + v * 10 + k + sd; trt <- letters[1:v]
    bk <- tryCatch(design.bib(trt, k, seed = seed, kinds = if (sd == 1) "Super-Duper" else "Mersenne-Twister")$book, error = function(e) NULL)
    if (is.null(bk)) next
    for (i in seq_len(nrow(bk))) cases[[length(cases) + 1]] <- case("bb", c(15, seed, sd, v, k, i - 1), match(as.character(bk[[3]][i]), trt) - 1, rel = 0, abs = 0)
  }
})))
# design.lattice: op 16 (16, seed, sd, k, r, idx) fn "lt" the treatment code at book row idx (r replicates of k * k plots)
invisible(capture.output(suppressMessages({
  for (k in 3:5) for (r in 2:3) for (sd in 0:1) {
    seed <- 1000 + k * 10 + r + 100 * sd; trt <- letters[1:(k * k)]
    bk <- design.lattice(trt, r = r, serie = 2, seed = seed, kinds = if (sd == 1) "Super-Duper" else "Mersenne-Twister")$book
    for (i in seq_len(nrow(bk))) cases[[length(cases) + 1]] <- case("lt", c(16, seed, sd, k, r, i - 1), match(as.character(bk[[4]][i]), trt) - 1, rel = 0, abs = 0)
  }
})))
# design.alpha: op 17 (17, seed, sd, ntr, k, r, idx) fn "ab" the treatment code at book row idx (the r replicates in turn, each block by block)
invisible(capture.output(suppressMessages({
  for (cfg in list(c(12, 3, 2), c(15, 3, 3), c(24, 4, 3), c(20, 4, 4), c(30, 5, 2), c(18, 3, 2))) for (sd in 0:1) {
    ntr <- cfg[1]; k <- cfg[2]; r <- cfg[3]; seed <- 1100 + ntr + k + r + 100 * sd; trt <- sprintf("T%02d", 1:ntr)
    bk <- tryCatch(design.alpha(trt, k, r, serie = 2, seed = seed, kinds = if (sd == 1) "Super-Duper" else "Mersenne-Twister")$book, error = function(e) NULL)
    if (is.null(bk)) next
    for (i in seq_len(nrow(bk))) cases[[length(cases) + 1]] <- case("ab", c(17, seed, sd, ntr, k, r, i - 1), match(as.character(bk[[4]][i]), trt) - 1, rel = 0, abs = 0)
  }
})))
# the grouping letters of kruskal and friedman with group = TRUE: fn "kgm"/"kgo" (kind 5 args plus idx) and "fgm"/"fgo" (kind 6 args plus idx), the mask and the treatment at sorted position idx
for (rep in 1:8) {
  k <- sample(4:6, 1); sz <- sample(4:7, 1); n <- k * sz
  g <- factor(rep(1:k, each = sz)); y <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), 4)
  kr <- kruskal(y, g, group = TRUE)$groups
  for (i in seq_len(nrow(kr))) {
    a <- c(5, n, k, y, as.numeric(g), i - 1)
    cases[[length(cases) + 1]] <- case("kgm", a, mask(as.character(kr$groups[i])), rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("kgo", a, as.numeric(rownames(kr)[i]), rel = 0, abs = 0)
  }
  nb <- sample(5:10, 1); nt <- sample(3:6, 1)
  m <- matrix(round(rnorm(nb * nt) + rep(seq_len(nt) * runif(1, 0, 0.5), each = nb), 3), nb, nt)
  dd <- data.frame(judge = factor(rep(seq_len(nb), nt)), trt = factor(rep(seq_len(nt), each = nb)), ev = as.vector(m))
  fg <- friedman(dd$judge, dd$trt, dd$ev, group = TRUE)$groups
  for (i in seq_len(nrow(fg))) {
    a <- c(6, nb, nt, as.vector(t(m)), i - 1)
    cases[[length(cases) + 1]] <- case("fgm", a, mask(as.character(fg$groups[i])), rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("fgo", a, as.numeric(rownames(fg)[i]), rel = 0, abs = 0)
  }
}
emit("agricolae_groups", "agricolae", list(cases))
