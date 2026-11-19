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
emit("agricolae_groups", "agricolae", list(cases))
