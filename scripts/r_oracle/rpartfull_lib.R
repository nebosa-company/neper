# Shared by the rpartfull_* groups. One dataset becomes a run of cases for tests/selfhost/fixtures/link/oracle_rpartfull:
#   case 0:  args = (0, n, p, method, ny, k, npar, minsplit, minbucket, cp, maxcompete, maxsurrogate, usesurrogate, surrogatestyle, maxdepth, xval, seed,
#                    parms[npar], ncat[p], cost[p], wt[n], y (row-major, ny columns), x (column-major, NA missing, factors as codes))
#            want = number of rows of the frame; the fixture keeps this fit for the cases after it.
#   queries: args = (what, prune cp or 0, extras...); each answer is a position-weighted sum  sum(v * seq_along(v))  of one piece of the rpart object:
#     1-6 cptable columns (rows, CP, nsplit, rel error, xerror, xstd), 10-20 frame (rows, id, n, wt, dev, yval, complexity, ncompete, nsurrogate, var, yval2),
#     30-37 splits (rows, count, ncat, improve, index, adj, var) and csplit, 40 where, 50-52 variable importance, 70-71 printcp (root node error, variables used),
#     60-64 predict(newdata) as vector, where, prob, class, matrix; 65-67 predict() of the training data as vector, prob, matrix.
suppressMessages(library(rpart))
suppressMessages(library(survival))
ck <- function(v) { v <- as.numeric(v); sum(v * seq_along(v)) }
mcode <- c(anova = 1, poisson = 2, class = 3, exp = 4)

rp_cases <- function(y, X, wt = NULL, cost = NULL, method = NULL, parms = NULL, ctl = list(), seed = 1, newX = NULL, prunes = numeric(), rel = 1e-9, abs = 1e-10) {
  n <- nrow(X); p <- ncol(X); vn <- colnames(X)
  d <- X; d$y__ <- y
  if (is.null(wt)) wt <- rep(1, n)
  fa <- list(formula = y__ ~ ., data = d, weights = wt, control = do.call(rpart.control, ctl))
  if (!is.null(method)) fa$method <- method
  if (!is.null(parms)) fa$parms <- parms
  if (!is.null(cost)) fa$cost <- cost
  set.seed(seed)
  fit <- do.call(rpart, fa)
  cs <- fit$control; mi <- unname(mcode[fit$method])
  isf <- vapply(X, is.factor, TRUE)
  ncat <- ifelse(isf, vapply(X, nlevels, 1L), 0L)
  xm <- do.call(cbind, lapply(X, as.numeric))
  if (is.null(cost)) cost <- rep(1, p)
  k <- 0; ymat <- NULL; ny <- 1; pv <- numeric()
  if (fit$method == "class") {
    k <- length(attr(fit, "ylevels")); ymat <- as.integer(factor(y)); ymat <- as.numeric(ymat)
    pv <- c(if (!is.null(parms$prior)) parms$prior else rep(NaN, k),
            if (!is.null(parms$loss)) as.vector(parms$loss) else rep(NaN, k * k),
            if (is.null(parms$split)) NaN else pmatch(parms$split, c("gini", "information")))
    if (is.null(parms)) pv <- numeric()
  } else if (fit$method == "poisson") {
    ny <- 2; ymat <- as.vector(t(cbind(y[, 1], y[, 2])))
    if (!is.null(parms)) pv <- c(if (is.null(parms$shrink)) NaN else parms$shrink, if (is.null(parms$method)) NaN else pmatch(parms$method, c("deviance", "sqrt")))
  } else if (fit$method == "exp") {
    ny <- 2; ymat <- as.vector(t(cbind(y[, 1], y[, 2])))
    if (!is.null(parms)) pv <- c(if (is.null(parms$shrink)) NaN else parms$shrink, if (is.null(parms$method)) NaN else pmatch(parms$method, c("deviance", "sqrt")))
  } else ymat <- as.numeric(y)
  head <- c(0, n, p, mi, ny, k, length(pv), cs$minsplit, cs$minbucket, cs$cp, cs$maxcompete, cs$maxsurrogate, cs$usesurrogate, cs$surrogatestyle, cs$maxdepth,
            if (length(cs$xval) == 1) cs$xval else 0, seed)
  cases <- list(case("rp", c(head, pv, ncat, cost, wt, ymat, as.vector(xm)), nrow(fit$frame), rel = rel, abs = abs))
  isclass <- fit$method == "class"
  nd <- NULL
  if (!is.null(newX)) {
    nd <- newX
  }
  fits <- list(list(0, fit))
  for (pc in prunes) fits[[length(fits) + 1]] <- list(pc, prune(fit, cp = pc))
  for (fp in fits) {
    pc <- fp[[1]]; f <- fp[[2]]
    add <- function(what, val, extra = numeric()) cases[[length(cases) + 1]] <<- case("rq", c(what, pc, extra), val, rel = rel, abs = abs)
    cpt <- f$cptable
    add(1, nrow(cpt)); add(2, ck(cpt[, 1])); add(3, ck(cpt[, 2])); add(4, ck(cpt[, 3]))
    add(5, if (ncol(cpt) >= 5) ck(cpt[, 4]) else 0); add(6, if (ncol(cpt) >= 5) ck(cpt[, 5]) else 0)
    fr <- f$frame
    add(10, nrow(fr)); add(11, ck(as.integer(rownames(fr)))); add(12, ck(fr$n)); add(13, ck(fr$wt)); add(14, ck(fr$dev)); add(15, ck(fr$yval))
    add(16, ck(fr$complexity)); add(17, ck(fr$ncompete)); add(18, ck(fr$nsurrogate)); add(19, ck(match(as.character(fr$var), c("<leaf>", vn)) - 1))
    add(20, if (!is.null(fr$yval2)) ck(as.vector(t(fr$yval2))) else 0)
    s <- f$splits
    if (is.null(s)) { for (w in c(30:36)) add(w, 0) } else {
      add(30, nrow(s)); add(31, ck(s[, "count"])); add(32, ck(s[, "ncat"])); add(33, ck(s[, "improve"])); add(34, ck(s[, "index"])); add(35, ck(s[, "adj"]))
      add(36, ck(match(rownames(s), vn)))
    }
    add(37, if (is.null(f$csplit)) 0 else ck(as.vector(t(f$csplit))))
    add(40, ck(f$where))
    vi <- f$variable.importance
    add(50, length(vi)); add(51, if (is.null(vi)) 0 else ck(vi)); add(52, if (is.null(vi)) 0 else ck(match(names(vi), vn)))
    add(70, fr$dev[1] / fr$n[1])
    used <- unique(as.character(fr$var[fr$var != "<leaf>"]))
    add(71, length(used) * 1000 + sum(match(used, vn)))
    pt <- if (isclass) "prob" else "vector"
    if (isclass) { add(65, ck(predict(f, type = "vector"))); add(66, ck(as.vector(t(predict(f, type = "prob"))))) } else add(65, ck(predict(f, type = "vector")))
    if (fit$method != "anova") add(67, ck(as.vector(t(predict(f, type = "matrix")))))
    if (!is.null(nd) && nrow(f$frame) > 1) {
      nn <- nrow(nd); nx <- as.vector(do.call(cbind, lapply(nd, as.numeric))); ex <- c(nn, nx)
      add(60, ck(predict(f, nd, type = "vector")), ex)
      mf <- model.frame(delete.response(f$terms), nd, na.action = na.pass, xlev = attr(f, "xlevels"))
      add(61, ck(rpart:::pred.rpart(f, rpart:::rpart.matrix(mf))), ex)
      if (isclass) {
        add(62, ck(as.vector(t(predict(f, nd, type = "prob")))), ex)
        add(63, ck(as.integer(predict(f, nd, type = "class"))), ex)
        add(64, ck(as.vector(t(predict(f, nd, type = "matrix")))), ex)
      } else if (fit$method != "anova") add(64, ck(as.vector(t(predict(f, nd, type = "matrix")))), ex)
    }
  }
  cases
}

rp_fac <- function(codes, L) factor(letters[codes], levels = letters[seq_len(L)])
