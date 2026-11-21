# afex aov_ez, Type III, any number of between and within factors, unequal cells.
#   args: (s mask, t mask, n subjects, nb, nw, nb between level counts, nw within level counts, then per subject: nb 0-based between levels, prod(wl) responses with the first within factor fastest)
#   fn names the slot: F dfn dfd p ges gg hf ggp hfp W pW SS; (s, t) is the bit mask of the effect's between and within factors.
suppressMessages(library(afex))
cases <- list()
slots <- c("F", "dfn", "dfd", "p", "ges", "gg", "hf", "ggp", "hfp", "W", "pW", "SS")
bn <- c("A", "B", "C"); wn <- c("X", "Y", "Z")
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
mask <- function(term, nms) { m <- 0; for (p in strsplit(term, ":")[[1]]) { i <- match(p, nms); if (!is.na(i)) m <- m + 2^(i - 1) }; m }
designs <- list(
  list(bl = integer(0), wl = c(3, 2), per = 8),
  list(bl = integer(0), wl = c(2, 2), per = 9),
  list(bl = integer(0), wl = c(3, 4), per = 10),
  list(bl = integer(0), wl = c(2, 2, 2), per = 10),
  list(bl = integer(0), wl = c(3, 2, 2), per = 12),
  list(bl = 2, wl = c(3, 2), per = c(6, 9)),
  list(bl = 3, wl = c(2, 2), per = c(5, 8, 6)),
  list(bl = c(2, 2), wl = 3, per = c(5, 6, 7, 4)),
  list(bl = c(2, 3), wl = 2, per = c(4, 5, 6, 5, 4, 7)),
  list(bl = 2, wl = c(2, 2, 2), per = c(7, 9)),
  list(bl = c(2, 2), wl = c(3, 2), per = c(5, 4, 6, 5)),
  list(bl = c(2, 3), wl = integer(0), per = c(4, 6, 5, 7, 4, 8)),
  list(bl = c(2, 2, 2), wl = integer(0), per = c(3, 4, 5, 3, 4, 6, 5, 3)),
  list(bl = 3, wl = integer(0), per = c(6, 9, 7)),
  list(bl = 2, wl = 5, per = c(11, 7))
)
set.seed(20261208)
for (d in designs) {
  nbf <- length(d$bl); nwf <- length(d$wl)
  cells <- if (nbf > 0) as.matrix(expand.grid(lapply(d$bl, function(l) 0:(l - 1)))) else matrix(0, 1, 0)
  grp <- cells[rep(seq_len(nrow(cells)), d$per), , drop = FALSE]
  n <- nrow(grp); ks <- if (nwf > 0) prod(d$wl) else 1
  wlev <- if (nwf > 0) as.matrix(expand.grid(lapply(d$wl, function(l) 0:(l - 1)))) else matrix(0, 1, 0)
  gm <- if (nbf > 0) rowSums(grp) * 0.4 else rep(0, n)
  y <- matrix(rnorm(n * ks), n) + rnorm(n) + gm + matrix(if (nwf > 0) rowSums(wlev) * 0.3 else 0, n, ks, byrow = TRUE)
  if (nwf > 0 && nbf > 0) y <- y + outer(grp[, 1], wlev[, 1] * 0.25)
  long <- data.frame(id = factor(rep(seq_len(n), each = ks)))
  for (f in seq_len(nbf)) long[[bn[f]]] <- factor(rep(grp[, f], each = ks), levels = 0:(d$bl[f] - 1))
  for (f in seq_len(nwf)) long[[wn[f]]] <- factor(rep(wlev[, f], n), levels = 0:(d$wl[f] - 1))
  long$y <- as.vector(t(y))
  di <- match(list(d), designs)
  if (di %% 2 == 0) {
  # aov_car formula interface on the even designs, aov_ez on the odd: same model, both checked against the engine
    err <- if (nwf > 0) paste0("Error(id/(", paste(wn[seq_len(nwf)], collapse = "*"), "))") else "Error(id)"
    a <- suppressMessages(aov_car(as.formula(paste0("y ~ ", if (nbf > 0) paste0(paste(bn[seq_len(nbf)], collapse = "*"), " + "), err)), long, type = 3))
  } else
  a <- suppressMessages(aov_ez("id", "y", long, between = if (nbf > 0) bn[seq_len(nbf)] else NULL, within = if (nwf > 0) wn[seq_len(nwf)] else NULL, type = 3))
  no <- anova(a, correction = "none", es = "ges")
  args0 <- c(n, nbf, nwf, d$bl, d$wl, as.vector(t(cbind(grp, y))))
  val <- list()
  for (term in rownames(no)) {
    s <- mask(term, bn); t <- mask(term, wn)
    v <- rep(NA_real_, 12)
    v[1] <- no[term, "F"]; v[2] <- no[term, "num Df"]; v[3] <- no[term, "den Df"]; v[4] <- no[term, "Pr(>F)"]; v[5] <- no[term, "ges"]
    val[[term]] <- list(s = s, t = t, v = v)
  }
  if (nwf > 0) {
    sm <- summary(a$Anova); ad <- sm$pval.adjustments; sp <- sm$sphericity.tests
    for (term in names(val)) {
      v <- val[[term]]$v
      if (term %in% rownames(ad) && is.finite(ad[term, "GG eps"])) { v[6] <- ad[term, "GG eps"]; v[7] <- ad[term, "HF eps"]; v[8] <- ad[term, "Pr(>F[GG])"]; v[9] <- ad[term, "Pr(>F[HF])"] }
      if (!is.null(sp) && term %in% rownames(sp)) { v[10] <- sp[term, "Test statistic"]; v[11] <- sp[term, "p-value"] }
      val[[term]]$v <- v
    }
    # effect SS from the multivariate summary
    for (term in names(val)) { r <- sm$univariate.tests; val[[term]]$v[12] <- r[term, "Sum Sq"] }
  } else {
    # between only: SS = F * dfn * MSE, recovered from ges = SS / (SS + sum of all SS) is not needed; take it from the lm table
    tab <- as.data.frame(a$Anova)
    for (term in names(val)) val[[term]]$v[12] <- tab[term, "Sum Sq"]
  }
  for (term in names(val)) {
    args <- c(val[[term]]$s, val[[term]]$t, args0)
    for (i in seq_along(slots)) add(slots[i], args, val[[term]]$v[i])
  }
}
emit("afexaov", "afex", list(cases))
