# ksamples: ad.test's AD statistic and standardised T.AD, both versions.
#   args: (version 1 or 2, part 0 AD or 1 T.AD, k, the k sizes..., the samples back to back...)
# ad.test returns its matrix rounded to 3 to 5 significant digits, so the golden values come from the same formulas in full
# precision (Scholz and Stephens 1987, eqs 6, 7 and the sigma_N polynomial) and are checked against ad.test to its rounding.
suppressMessages(library(kSamples))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
adstat <- function(lst, ver) {
  k <- length(lst); n <- sapply(lst, length); N <- sum(n); z <- sort(unlist(lst)); zs <- unique(z)
  l <- as.numeric(table(factor(z, levels = zs))); B <- cumsum(l); s <- 0
  for (i in 1:k) {
    f <- as.numeric(table(factor(lst[[i]], levels = zs)))
    if (ver == 1) { M <- cumsum(f); j <- B[-length(B)]; s <- s + sum(l[-length(l)] * (N * M[-length(M)] - n[i] * j)^2 / (j * (N - j))) / n[i] }
    else { Ba <- B - l / 2; M <- cumsum(f) - f / 2; s <- s + sum(l * (N * M - n[i] * Ba)^2 / (Ba * (N - Ba) - N * l / 4)) / n[i] }
  }
  if (ver == 1) s / N else (N - 1) / N^2 * s
}
sg <- function(n) {
  k <- length(n); N <- sum(n); H <- sum(1 / n); h <- sum(1 / (1:(N - 1))); g <- 0
  for (i in 1:(N - 2)) for (j in (i + 1):(N - 1)) g <- g + 1 / ((N - i) * j)
  a <- (4 * g - 6) * (k - 1) + (10 - 6 * g) * H
  b <- (2 * g - 4) * k^2 + 8 * h * k + (2 * g - 14 * h - 4) * H - 8 * h + 4 * g - 6
  c <- (6 * h + 2 * g - 2) * k^2 + (4 * h - 4 * g + 6) * k + (2 * h - 6) * H + 4 * h
  d <- (2 * h + 6) * k^2 - 4 * h * k
  sqrt((a * N^3 + b * N^2 + c * N + d) / ((N - 1) * (N - 2) * (N - 3)))
}
set.seed(20261990)
for (rep in 1:30) {
  k <- sample(2:5, 1); n <- sample(4:15, k, TRUE); ties <- rep %% 2 == 0
  lst <- lapply(n, function(m) { v <- rnorm(m, runif(1, -0.5, 0.5), runif(1, 0.8, 1.5)); if (ties) round(v, 0) else round(v, 5) })
  r <- do.call(ad.test, c(lst, list(method = "asymptotic")))$ad
  a <- c(k, n, unlist(lst))
  for (v in 1:2) {
    ad <- adstat(lst, v); tt <- (ad - (k - 1)) / sg(n)
    stopifnot(abs(ad - r[v, 1]) <= 0.006 * max(abs(r[v, 1]), 1), abs(tt - r[v, 2]) <= 0.006 * max(abs(r[v, 2]), 1))
    add("ad", c(v, 0, a), ad); add("ad", c(v, 1, a), tt)
  }
}
# ad.pval(tx, m, version): "pv" (version, m, tx)
for (rep in 1:80) {
  v <- sample(1:2, 1); m <- sample(c(1:12, 15, 20, 30), 1); tx <- sample(c(runif(1, -1.8, 0), runif(1, 0, 3), runif(1, 3, 8)), 1)
  add("pv", c(v, m, tx), ad.pval(tx, m, v))
}
emit("ksamples", "kSamples", list(cases))
