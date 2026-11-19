# MASS stepAIC, dropterm and addterm beyond lm with single-column terms: lm, Poisson, binomial and glm.nb fits, factor and interaction terms under marginality,
# Tolerance 1e-6 for the glm families: the glm IRLS deviance and AIC sum exp/log/lgamma terms that differ by an ulp from R (mass_probe.R); measured group maximum is about 1e-6
# a scope with lower and upper, no scope, k = 2 and log(n), a scale, a step limit, and the F / Chisq tests.
# Args: (mode, fam 0 lm 1 poisson 2 binomial 3 negbin, n, p, nt, dir 0 both 1 backward 2 forward, k, scale, steps, test 0 none 1 Chisq 2 F, nstart, start[nstart],
#        X[n p] col-major, assign[p], vmask[nt], y[n], lower[nt], upper[nt])
#   mode 0  stepAIC: the number of models and the path sum_i (i - 1) * (signed term), exact
#   mode 1  stepAIC: final extractAIC + 5 edf + 0.37 sum(Resid. Dev) + 0.11 sum(AIC)
#   mode 2  dropterm(start) and mode 3 addterm(start, upper): the position-weighted columns of the table, summed with column weights 1, 2, 3...
suppressMessages(library(MASS))
cases <- list()
set.seed(20262701)
vars <- c("a", "b", "f", "g")
uppers <- c("~ a + b + f + g", "~ a * b + f + g", "~ a * f + b + g", "~ a + b + f * g", "~ a * b + f", "~ a + f * g")
canon <- function(l) vapply(strsplit(l, ":"), function(p) paste(p[order(match(p, vars))], collapse = ":"), "")
vmask_of <- function(l) sum(2^(match(strsplit(l, ":")[[1]], vars) - 1))

make_data <- function(n, fam) {
  d <- data.frame(a = round(rnorm(n), 4), b = round(rnorm(n), 4), f = factor(sample(c("p", "q", "r"), n, TRUE)), g = factor(sample(c("u", "v"), n, TRUE)))
  eta <- 0.4 * d$a - 0.5 * d$b + c(0, 0.5, -0.4)[as.integer(d$f)] + 0.3 * (d$g == "v") + 0.3 * d$a * (d$f == "q")
  d$y <- switch(fam + 1,
    round(1 + eta + rnorm(n, 0, 1.2), 4),
    rpois(n, exp(0.3 + 0.6 * eta)),
    rbinom(n, 1, plogis(0.7 * eta)),
    rnbinom(n, size = 2.5, mu = exp(0.5 + 0.6 * eta)))
  d
}
fit_of <- function(fam, f, d) switch(fam + 1, lm(f, d), glm(f, poisson, d), glm(f, binomial, d), glm.nb(f, d))
fs <- function(labels) if (length(labels)) as.formula(paste("y ~", paste(labels, collapse = " + "))) else as.formula("y ~ 1")

closed_subset <- function(labels) {
  keep <- sample(c(TRUE, FALSE), length(labels), TRUE)
  repeat {
    ch <- FALSE
    for (i in which(keep)) {
      parts <- strsplit(labels[i], ":")[[1]]
      if (length(parts) > 1) for (m in 1:(length(parts) - 1)) for (s in combn(parts, m, simplify = FALSE)) {
        j <- match(canon(paste(s, collapse = ":")), labels)
        if (!is.na(j) && !keep[j]) { keep[j] <- TRUE; ch <- TRUE }
      }
    }
    if (!ch) break
  }
  labels[keep]
}

lbl_idx <- function(l, ul) match(canon(l), ul)
signed <- function(step) { s <- trimws(step); sg <- ifelse(substr(s, 1, 1) == "+", 1, -1); list(sg = sg, term = trimws(substring(s, 2))) }

for (rep in 1:44) {
  fam <- c(0, 0, 1, 2, 3, 1, 2, 0, 3)[(rep - 1) %% 9 + 1]
  n <- sample(60:110, 1)
  d <- make_data(n, fam)
  up <- as.formula(paste("y", sample(uppers, 1)))
  tl <- attr(terms(up), "term.labels"); ul <- canon(tl); nt <- length(ul)
  X <- model.matrix(up, d); asg <- attr(X, "assign"); p <- ncol(X)
  vmask <- vapply(ul, vmask_of, 0)
  style <- rep %% 4
  start <- switch(style + 1, character(0), ul, closed_subset(ul), closed_subset(ul))
  lowr <- if (style == 3 && "a" %in% ul) { start <- union("a", start); "a" } else character(0)
  start <- ul[ul %in% start]
  dir <- sample(c("both", "backward", "forward"), 1)
  if (dir == "forward" && length(start) == nt) start <- start[-length(start)]
  noscope <- (rep %% 5 == 0) && dir != "forward"
  if (noscope) lowr <- character(0)
  kk <- if (rep %% 3 == 0) log(n) else 2
  scl <- if (fam == 0 && rep %% 7 == 0) 1.7 else 0
  steps <- if (rep %% 11 == 0) 2 else 1000
  startf <- fs(start)
  f0 <- tryCatch(fit_of(fam, startf, d), error = function(e) NULL, warning = function(w) suppressWarnings(fit_of(fam, startf, d)))
  if (is.null(f0)) next
  r <- suppressWarnings(tryCatch(
    if (noscope) stepAIC(f0, direction = dir, k = kk, scale = scl, steps = steps, trace = 0)
    else stepAIC(f0, scope = list(lower = as.formula(paste("~", if (length(lowr)) paste(lowr, collapse = "+") else "1")), upper = as.formula(paste("~", paste(ul, collapse = "+")))), direction = dir, k = kk, scale = scl, steps = steps, trace = 0),
    error = function(e) NULL))
  if (is.null(r)) next
  upflag <- if (noscope) as.numeric(ul %in% start) else rep(1, nt)
  loflag <- as.numeric(ul %in% lowr)
  stt <- match(start, ul)
  hdr <- function(mode, test) c(mode, fam, n, p, nt, match(dir, c("both", "backward", "forward")) - 1, kk, scl, steps, test, length(stt), stt)
  body <- c(as.vector(X), asg, vmask, d$y, loflag, upflag)
  an <- r$anova
  nm <- nrow(an)
  path <- 0
  if (nm > 1) { sg <- signed(as.character(an$Step[-1])); path <- sum((seq_len(nm - 1)) * sg$sg * lbl_idx(sg$term, ul)) }
  cases[[length(cases) + 1]] <- case("stepx", c(hdr(0, 0), body), nm * 100000 + path, rel = 0, abs = 0)
  e <- extractAIC(r, scale = scl, k = kk)
  devcol <- an[["Resid. Dev"]]
  cases[[length(cases) + 1]] <- case("stepx", c(hdr(1, 0), body), e[2] + 5 * e[1] + 0.37 * sum(devcol) + 0.11 * sum(if (is.null(an$AIC)) an$Cp else an$AIC), rel = if (fam == 3) 1e-6 else 1e-9, abs = 1e-9)
}

# the tables
tbl_sum <- function(tb) {
  nm <- colnames(tb); v <- 0
  pick <- function(pat) { j <- grep(pat, nm, ignore.case = TRUE)[1]; if (is.na(j)) NULL else tb[[j]] }
  cols <- list(pick("^Df$"), pick("^(RSS|Deviance)$"), pick("^(AIC|Cp)$"), pick("^(LRT|F Value|scaled dev[.])$"), pick("^Pr"))
  for (c in seq_along(cols)) { x <- cols[[c]]; if (!is.null(x)) { w <- seq_along(x) * c; ok <- !is.na(x); v <- v + sum(w[ok] * x[ok]) } }
  v
}
for (rep in 1:36) {
  fam <- c(0, 1, 2, 0, 1, 2, 3)[(rep - 1) %% 7 + 1]
  n <- sample(60:110, 1)
  d <- make_data(n, fam)
  up <- as.formula(paste("y", sample(uppers, 1)))
  tl <- attr(terms(up), "term.labels"); ul <- canon(tl); nt <- length(ul)
  X <- model.matrix(up, d); asg <- attr(X, "assign"); p <- ncol(X)
  vmask <- vapply(ul, vmask_of, 0)
  start <- ul[ul %in% closed_subset(ul)]
  if (rep %% 4 == 0) start <- ul
  if (length(start) == nt && rep %% 2 == 1) start <- start[-length(start)]
  f0 <- suppressWarnings(tryCatch(fit_of(fam, fs(start), d), error = function(e) NULL))
  if (is.null(f0)) next
  test <- (rep %% 3)
  testn <- c("none", "Chisq", "F")[test + 1]
  if (fam == 3 && testn == "F") { test <- 1; testn <- "Chisq" }
  kk <- if (rep %% 5 == 0) log(n) else 2
  scl <- if (fam == 0 && rep %% 2 == 0) 1.3 else 0
  stt <- match(start, ul)
  body <- c(as.vector(X), asg, vmask, d$y, rep(0, nt), rep(1, nt))
  for (mode in 2:3) {
    tb <- suppressWarnings(tryCatch(
      if (mode == 2) dropterm(f0, test = testn, k = kk, scale = scl) else addterm(f0, scope = up, test = testn, k = kk, scale = scl),
      error = function(e) NULL))
    if (is.null(tb) || nrow(tb) < 2) next
    cases[[length(cases) + 1]] <- case("stepx", c(mode, fam, n, p, nt, 0, kk, scl, 1000, test, length(stt), stt, body), tbl_sum(tb), rel = 1e-8, abs = 1e-9)
  }
}
emit("mass_stepx", "MASS", list(cases))
