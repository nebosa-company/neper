# stepGAIC on main-effect terms of one distribution parameter, families 0 NO 1 GA 3 WEI 4 BCCG (RS fits, unit weights).
# A scenario opens with a case whose args are the 16-number header, init (ninit indices into the candidate columns), lower (q flags), upper (q flags) and the data;
# the cases after it carry fam 99 and the header only.
# header: fam, algo (0), n, what (0 mu, 1 sigma, 2 nu), q, ninit, direction (0 both, 1 backward, 2 forward), k, columns of the mu, sigma and nu design (0 for `what`),
#         link kinds of mu, sigma, nu (4 identity, 5 log), out kind, out index
# data: y (n), w (n), the fixed designs one after the other (column-major), the q candidate columns (n each)
# out kinds: 0 number of final terms, 1 final term i (index into the candidates), 2 number of models on the path, 3 change i (signed index + 1, 0 for the start),
#            4 resid. deviance of path model i, 5 AIC of path model i, 6 resid. df of path model i
suppressMessages(library(gamlss))
cases <- list()
famobj <- list(NO, GA, PO, WEI, BCCG)
np_of <- c(2, 2, 1, 2, 3)
pn <- c("mu", "sigma", "nu")
mk <- function(fam, y, d, cn, fixed, what, init, lower, upper, dir, k, links, rel = 1e-9) {
  n <- length(y)
  d$y <- y
  assign("dd", d, envir = globalenv())
  np <- np_of[fam + 1]
  lk <- c("identity", "log")[links - 3]
  fo <- do.call(famobj[[fam + 1]], as.list(lk[seq_len(np)]))
  rhs <- fixed
  rhs[what + 1] <- if (length(init)) paste(cn[init + 1], collapse = " + ") else "1"
  a <- list(formula = as.formula(paste("y ~", rhs[1])), family = fo, data = quote(dd), trace = FALSE)
  if (np > 1) a$sigma.formula <- as.formula(paste("~", rhs[2]))
  if (np > 2) a$nu.formula <- as.formula(paste("~", rhs[3]))
  m0 <- suppressWarnings(eval(as.call(c(list(as.name("gamlss")), a))))
  tl <- function(v) if (length(v)) paste(cn[v + 1], collapse = " + ") else "1"
  sc <- list(lower = as.formula(paste("~", tl(which(lower == 1) - 1))), upper = as.formula(paste("~", tl(which(upper == 1) - 1))))
  dirn <- c("both", "backward", "forward")[dir + 1]
  m <- suppressWarnings(stepGAIC(m0, scope = sc, direction = dirn, what = pn[what + 1], k = k, trace = FALSE))
  an <- m$anova
  chg <- trimws(as.character(an$Step))
  code <- vapply(chg, function(s) {
    if (s == "") return(0)
    sg <- if (substr(s, 1, 1) == "+") 1 else -1
    sg * (match(trimws(substr(s, 2, nchar(s))), cn))
  }, 0)
  fin <- attr(terms(m, pn[what + 1]), "term.labels")
  X <- lapply(seq_len(np), function(j) if (j == what + 1) NULL else model.matrix(as.formula(paste("~", rhs[j])), d))
  pf <- vapply(seq_len(3), function(j) if (j > np || j == what + 1) 0 else ncol(X[[j]]), 1)
  lks <- c(links, 4)[1:3]
  hdr <- function(f, kind, idx) c(f, 0, n, what, length(cn), length(init), dir, k, pf, lks, kind, idx)
  cand <- unlist(lapply(cn, function(v) d[[v]]))
  data <- c(init, lower, upper, y, rep(1, n), unlist(lapply(X, function(z) if (is.null(z)) NULL else as.vector(z))), cand)
  first <- TRUE
  add <- function(kind, idx, want, r = rel) {
    h <- hdr(if (first) fam else 99, kind, idx)
    cases[[length(cases) + 1]] <<- case("step", if (first) c(h, data) else h, want, rel = r, abs = if (r == 0) 0 else 1e-11)
    first <<- FALSE
  }
  add(0, 0, length(fin), r = 0)
  for (j in seq_along(fin)) add(1, j - 1, match(fin[j], cn) - 1, r = 0)
  add(2, 0, nrow(an), r = 0)
  for (i in seq_len(nrow(an))) {
    add(3, i - 1, code[i], r = 0)
    add(4, i - 1, an[["Resid. Dev"]][i])
    add(5, i - 1, an$AIC[i])
    add(6, i - 1, an[["Resid. Df"]][i])
  }
}
n <- 80
set.seed(20261801)
x1 <- round(runif(n, 0, 5), 3); x2 <- round(rnorm(n), 3); x3 <- round(runif(n), 3); x4 <- round(rnorm(n, 1, 2), 3); x5 <- round(runif(n, -1, 1), 3)
d0 <- data.frame(x1 = x1, x2 = x2, x3 = x3, x4 = x4, x5 = x5)
cn <- c("x1", "x2", "x3", "x4", "x5")
one <- rep(1, 5)
yno <- round(2 + 0.7 * x1 - 0.6 * x2 + exp(-0.5 + 0.25 * x1) * rnorm(n), 4)
mk(0, yno, d0, cn, c("1", "1", "1"), 0, integer(0), c(0, 0, 0, 0, 0), one, 0, 2, c(4, 5, 4))
mk(0, yno, d0, cn, c("1", "1", "1"), 0, integer(0), c(0, 0, 0, 0, 0), one, 0, log(n), c(4, 5, 4))
mk(0, yno, d0, cn, c("1", "1", "1"), 0, 0:4, c(0, 0, 0, 0, 0), one, 1, 2, c(4, 5, 4))
mk(0, yno, d0, cn, c("1", "1", "1"), 0, c(2, 4), c(0, 0, 1, 0, 0), one, 0, 2, c(4, 5, 4))
mk(0, yno, d0, cn, c("x1", "1", "1"), 1, integer(0), c(0, 0, 0, 0, 0), one, 2, 2, c(4, 5, 4))
mk(0, yno, d0, cn, c("x1 + x2", "1", "1"), 1, c(0, 3), c(0, 0, 0, 0, 0), one, 0, 2, c(4, 5, 4))
yga <- round(rgamma(n, shape = 5, scale = exp(0.4 + 0.25 * x1) / 5) + 0.01, 4)
mk(1, yga, d0, cn, c("1", "1", "1"), 0, integer(0), c(0, 0, 0, 0, 0), one, 0, 2, c(5, 5, 4))
mk(1, yga, d0, cn, c("1", "1", "1"), 0, 0:4, c(0, 0, 0, 0, 0), one, 1, 2, c(5, 5, 4))
ywe <- round(rweibull(n, shape = 2.2, scale = exp(0.8 + 0.12 * x1 - 0.15 * x2)), 4)
mk(3, ywe, d0, cn, c("1", "1", "1"), 0, integer(0), c(0, 0, 0, 0, 0), one, 0, 2, c(5, 5, 4))
ybc <- round(exp(1 + 0.15 * x1 - 0.1 * x4 + 0.2 * rnorm(n)), 4)
mk(4, ybc, d0, cn, c("1", "1", "1"), 0, integer(0), c(0, 0, 0, 0, 0), one, 0, 2, c(5, 5, 4))
mk(4, ybc, d0, cn, c("1", "1", "1"), 0, 0:4, c(0, 0, 0, 0, 0), one, 1, log(n), c(5, 5, 4))
emit("gamlss_step", c("gamlss", "gamlss.dist"), list(cases))
