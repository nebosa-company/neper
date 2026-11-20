# qca_e2e: truthTable() with inclusion, n and PRI cut-offs on crisp and fuzzy data, then minimize() of that table, compared as the text of qca_min.
#   args: (kind 0 complex, 1 parsimonious, 2 intermediate, 3 and 4 the PI chart rows of 0 and 1, incl.cut, n.cut, pri.cut, n, k, de[k] per condition 0 none 1 absent 2 present, data[n * (k + 1)] row-major, the conditions first, the outcome last)
#   The configurations with OUT "?" (empty or fewer than n.cut cases) are the remainders the include = "?" calls take as don't cares.
suppressMessages(library(QCA))
cases <- list()
set.seed(20262804)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("e2e", args, want, rel = 0, abs = 0)
srt <- function(x) sort(x, method = "radix")
for (rep in 1:60) {
  n <- sample(20:40, 1); k <- sample(3:5, 1); fuzzy <- rep %% 2 == 0
  X <- matrix(if (fuzzy) round(runif(n * k), 3) else rbinom(n * k, 1, 0.5), n, k)
  y <- if (fuzzy) round(pmin(1, pmax(0, X[, 1] * 0.7 + X[, 2] * 0.3 * runif(1) + runif(n, 0, 0.4))), 3) else as.numeric(X[, 1] == 1 & (X[, 2] == 1 | runif(n) < 0.3) | runif(n) < 0.1)
  d <- data.frame(X, Y = y); names(d) <- c(LETTERS[1:k], "Y")
  ic <- sample(c(0.6, 0.75, 0.9, 1), 1); nc <- sample(1:2, 1); pc <- sample(c(0, 0.3), 1)
  tt <- tryCatch(suppressWarnings(truthTable(d, outcome = "Y", conditions = LETTERS[1:k], incl.cut = ic, n.cut = nc, pri.cut = pc)), error = function(e) NULL)
  if (is.null(tt)) next
  t <- unclass(tt)$tt
  if (nrow(t) != 2^k || sum(t$OUT == 1) < 1 || sum(t$OUT == 0) < 1) next
  pistr <- function(s) { ch <- rep("-", k); for (tk in strsplit(s, "*", fixed = TRUE)[[1]]) { ng <- substr(tk, 1, 1) == "~"; ch[match(sub("~", "", tk), LETTERS)] <- if (ng) "0" else "1" }; paste(ch, collapse = "") }
  modtxt <- function(pis) paste(srt(vapply(pis, pistr, "")), collapse = "+")
  soltxt <- function(sol) { if (!is.list(sol)) sol <- list(sol); paste(srt(vapply(sol, modtxt, "")), collapse = ";") }
  chart <- function(m) modtxt(rownames(m$PIchart))
  a <- function(kind, de = rep(0, k)) c(kind, ic, nc, pc, n, k, de, as.vector(t(cbind(X, y))))
  m0 <- tryCatch(suppressWarnings(minimize(tt, include = "", details = TRUE)), error = function(e) NULL)
  if (!is.null(m0) && length(m0$solution) > 0 && length(m0$solution) < 200) { add(a(0), soltxt(m0$solution)); add(a(3), chart(m0)) }
  if (!any(t$OUT == "?")) next
  m1 <- tryCatch(suppressWarnings(minimize(tt, include = "?", details = TRUE)), error = function(e) NULL)
  if (!is.null(m1) && length(m1$solution) > 0 && length(m1$solution) < 200) { add(a(1), soltxt(m1$solution)); add(a(4), chart(m1)) }
  nv <- sample(1:k, 1); vs <- sample(k, nv); pol <- sample(1:2, nv, TRUE); de <- rep(0, k); de[vs] <- pol
  des <- paste(ifelse(pol == 1, "~", ""), LETTERS[vs], sep = "", collapse = ",")
  m2 <- tryCatch(suppressWarnings(minimize(tt, include = "?", dir.exp = des, details = TRUE)), error = function(e) NULL)
  if (is.null(m2) || is.null(m2$i.sol) || length(m2$i.sol) == 0 || length(m2$i.sol) > 60) next
  ent <- vapply(m2$i.sol, function(i) paste(modtxt(i$c.sol), modtxt(i$p.sol), soltxt(i$solution), sep = "|"), "")
  add(a(2, de), paste(srt(ent), collapse = "#"))
}
emit("qca_e2e", "QCA", list(cases))
