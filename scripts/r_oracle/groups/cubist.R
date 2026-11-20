# Cubist: rule-based regression models with committees and nearest-neighbor corrections, fitted by the package C code.
#   args: (n, p, committees, unbiased, rules, extrapolation (fraction), sample (fraction), seed, maxd (-1: set it from the random
#          stream, as the first fit of a session and a fit with sample > 0 can), neighbors, nq,
#          kind[p] (0 numeric, 1 factor, 2 ordered), nlev[p], the n training columns, y, the nq columns of the cases to predict).
#   A numeric column and y are sent in hundredths (every value has two decimals), a factor as its level codes, a missing value as NA.
#   fn "nrules" "cover" "mean" "lohi" "esterr" "cond" "cut" "coef": checksums over the model text the package writes (rule count,
#      sum of rule * cover, mean, lo + 2 hi, estimated error, condition codes, cut values, coefficients).
#   fn "usage_c" "usage_m": the sum of column * percent of the attribute usage table (conditions, models).
#   fn "eval_err" "eval_rel" "eval_cor": the evaluation lines of the report on the training data (as printed).
#   fn "pred": the sum of position * prediction of predict() at `neighbors`; fn "maxd": the close distance kept for the neighbors.
library(Cubist)
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel, abs)

enc <- function(x, y, q, committees, unbiased, rules, extrap, sample, seed, maxd, nb) {
  p <- ncol(x)
  kind <- sapply(x, function(v) if (is.ordered(v)) 2 else if (is.factor(v)) 1 else 0)
  nlev <- sapply(x, function(v) if (is.factor(v)) nlevels(v) else 0)
  col <- function(d) unlist(lapply(seq_len(p), function(j) {
    v <- d[[j]]
    if (kind[j] == 0) round(v * 100) else as.integer(v)
  }))
  c(nrow(x), p, committees, unbiased, rules, extrap / 100, sample / 100, seed, maxd, nb, nrow(q), kind, nlev, col(x), round(y * 100), col(q))
}

model_sums <- function(m, x) {
  lines <- strsplit(m$model, "\n")[[1]]
  nm <- names(x)
  out <- numeric(8)
  g <- 0; j <- 0
  kv <- function(l) {
    mm <- regmatches(l, gregexpr('[a-z]+="[^"]*"', l))[[1]]
    setNames(sub('^[a-z]+="(.*)"$', "\\1", mm), sub('^([a-z]+)=.*$', "\\1", mm))
  }
  for (l in lines) {
    if (startsWith(l, "conds=")) {
      v <- kv(l); g <- g + 1
      out[1] <- out[1] + 1
      out[2] <- out[2] + g * as.numeric(v["cover"])
      out[3] <- out[3] + g * as.numeric(v["mean"])
      out[4] <- out[4] + g * (as.numeric(v["loval"]) + 2 * as.numeric(v["hival"]))
      out[5] <- out[5] + g * as.numeric(v["esterr"])
    } else if (startsWith(l, "type=")) {
      j <- j + 1
      v <- kv(l)
      ty <- as.numeric(v["type"]); var <- match(v["att"], nm)
      lev <- levels(x[[var]])
      if (ty == 2) {
        sel <- if (v["result"] == "<=") 2 else 3
        out[7] <- out[7] + j * as.numeric(v["cut"])
      } else if (ty == 1) {
        sel <- match(v["val"], lev)
      } else {
        el <- regmatches(sub(".*elts=", "", l), gregexpr('"[^"]*"', sub(".*elts=", "", l)))[[1]]
        el <- gsub('"', "", el)
        sel <- sum(2^(match(el, lev) - 1))
      }
      out[6] <- out[6] + j * (ty * 10000 + (var) * 100 + sel)
    } else if (startsWith(l, "coeff=")) {
      toks <- regmatches(l, gregexpr('[a-z]+="[^"]*"', l))[[1]]
      vals <- sub('^[a-z]+="(.*)"$', "\\1", toks)
      out[8] <- out[8] + as.numeric(vals[1]) * (g * 17 + 1)
      k <- 2
      while (k <= length(vals)) {
        pos <- match(vals[k], nm)
        out[8] <- out[8] + as.numeric(vals[k + 1]) * (g * 17 + pos + 1)
        k <- k + 2
      }
    }
  }
  out
}

evalnum <- function(m, pat) {
  l <- grep(pat, strsplit(m$output, "\n")[[1]], value = TRUE)
  as.numeric(sub(paste0(".*", pat, "\\s+"), "", l))[1]
}

run <- function(x, y, q, committees = 1, unbiased = FALSE, rules = 100, extrap = 100, sample = 0, seed = 1,
                nbs = c(0, 1, 3, 5, 9), check_maxd = FALSE) {
  m <- cubist(x, y, committees = committees, control = cubistControl(unbiased = unbiased, rules = rules, extrapolation = extrap,
                                                                      sample = sample, seed = seed))
  # the C code sets its seed from the clock (init in the model header), so the value actually used is what is replayed
  if (sample > 0) seed <- as.integer(regmatches(m$model, regexpr("init=\"[0-9]+", m$model)) |> sub(pattern = "init=.", replacement = ""))
  base <- enc(x, y, q, committees, unbiased, rules, extrap, sample, seed, m$maxd, 0)
  s <- model_sums(m, x)
  fns <- c("nrules", "cover", "mean", "lohi", "esterr", "cond", "cut", "coef")
  for (i in 1:8) add(fns[i], base, s[i])
  ul <- strsplit(m$output, "
")[[1]]
  ul <- ul[(grep("Attribute usage", ul) + 3):length(ul)]
  ul <- ul[grepl("^	  ", ul) & nzchar(trimws(ul))]
  pct <- function(s) { s <- trimws(s); if (nzchar(s)) as.numeric(sub("%", "", s)) else 0 }
  idx <- match(trimws(substring(ul, 19)), names(x))
  add("usage_c", base, sum(idx * vapply(substring(ul, 4, 7), pct, 0)))
  add("usage_m", base, sum(idx * vapply(substring(ul, 11, 14), pct, 0)))
  add("eval_err", base, evalnum(m, "Average  \\|error\\|"), rel = 1e-12, abs = 1e-12)
  add("eval_rel", base, evalnum(m, "Relative \\|error\\|"), rel = 1e-12, abs = 1e-12)
  add("eval_cor", base, evalnum(m, "Correlation coefficient"), rel = 1e-12, abs = 1e-12)
  for (nb in nbs) {
    a <- enc(x, y, q, committees, unbiased, rules, extrap, sample, seed, m$maxd, nb)
    add("pred", a, sum(predict(m, q, neighbors = nb) * seq_len(nrow(q))))
  }
  if (check_maxd) add("maxd", enc(x, y, q, committees, unbiased, rules, extrap, sample, seed, -1, 1), m$maxd, rel = 0, abs = 1e-12)
  m
}

mk <- function(seed, n, nq, p = 4, nf = 0, nord = 0, nmiss = 0, grid = FALSE, noise = 0.4) {
  set.seed(seed)
  tot <- n + nq
  d <- data.frame(a = round(rnorm(tot), 2), b = round(runif(tot) * 10, if (grid) 0 else 1))
  if (p >= 3) d$c <- round(rnorm(tot, 2, 1.5), 2)
  if (p >= 4) d$d <- round(runif(tot, -3, 3), 2)
  if (p >= 5) d$e <- round(rnorm(tot) * 4, if (grid) 0 else 2)
  if (nf >= 1) d$f <- factor(sample(c("u", "v", "w"), tot, TRUE))
  if (nf >= 2) d$g <- factor(sample(c("yes", "no"), tot, TRUE))
  if (nord >= 1) d$h <- factor(sample(c("lo", "mid", "hi", "top"), tot, TRUE), levels = c("lo", "mid", "hi", "top"), ordered = TRUE)
  eff <- 2 * d$a + 0.3 * d$b + ifelse(d$a > 0.3, 1.5 * d$b, 0)
  if (nf >= 1) eff <- eff + ifelse(d$f == "u", 3, ifelse(d$f == "v", -1, 0))
  if (nf >= 2) eff <- eff + ifelse(d$g == "yes", 1, 0)
  if (nord >= 1) eff <- eff + as.integer(d$h)
  y <- round(eff + rnorm(tot, 0, noise), 2)
  if (nmiss > 0) {
    for (k in seq_len(nmiss)) {
      col <- sample(ncol(d), 1); rows <- sample(tot, max(2, tot %/% 12))
      d[rows, col] <- NA
    }
  }
  tr <- seq_len(n)
  list(x = d[tr, , drop = FALSE], y = y[tr], q = d[n + seq_len(nq), , drop = FALSE])
}

# the very first fit of the session: the random stream of the C code is untouched, so the close distance can be checked
d1 <- mk(11, 60, 10, p = 4)
run(d1$x, d1$y, d1$q, check_maxd = TRUE, nbs = c(0, 1, 3, 5, 9))
# committees, factors and missing values
d2 <- mk(12, 80, 12, p = 4, nf = 2, nmiss = 2)
run(d2$x, d2$y, d2$q, committees = 3, nbs = c(0, 1, 3, 9))
# an ordered factor, ties (a coarse grid), unbiased rules and an extrapolation limit
d3 <- mk(13, 90, 12, p = 5, nf = 1, nord = 1, grid = TRUE)
run(d3$x, d3$y, d3$q, committees = 2, unbiased = TRUE, extrap = 50, nbs = c(0, 2, 5, 9))
# a sample of the data, which also restarts the random stream
d4 <- mk(14, 100, 12, p = 3, nf = 1)
run(d4$x, d4$y, d4$q, committees = 2, sample = 70, seed = 23, check_maxd = TRUE, nbs = c(0, 1, 4))
# a limit on the number of rules
d5 <- mk(15, 120, 12, p = 5, nf = 1, nmiss = 1)
run(d5$x, d5$y, d5$q, committees = 4, rules = 3, nbs = c(0, 3, 9))
emit("cubist", "Cubist", list(cases))
