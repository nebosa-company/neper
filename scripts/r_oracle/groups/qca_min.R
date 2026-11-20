# qca_min: the models of QCA minimize() on a crisp truth table, compared as text.
#   args: (kind, n, n_on, n_dc, on minterms..., dc minterms (the unobserved configurations)..., de[n] per condition 0 none 1 absent 2 present); a minterm is the row number, the first condition the most significant bit.
#   kind 0 complex models (include = ""), 1 parsimonious models (include = "?"), 2 intermediate solutions (include = "?", dir.exp), 3 prime implicant chart rows of kind 0, 4 of kind 1.
#   text: a prime is one character per condition (1 present, 0 negated, - minimized), a model its primes sorted and joined by "+", models sorted and joined by ";";
#   kind 2 is one "complex|parsimonious|models" entry per pair, sorted and joined by "#"; kinds 3 and 4 are one model of all the chart rows.
suppressMessages(library(QCA))
cases <- list()
set.seed(20262801)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("min", args, want, rel = 0, abs = 0)
srt <- function(x) sort(x, method = "radix")
for (rep in 1:90) {
  n <- sample(3:5, 1); tt <- expand.grid(rep(list(0:1), n)); names(tt) <- LETTERS[1:n]; tt$OUT <- sample(c(1, 0), nrow(tt), TRUE, prob = c(0.4, 0.6))
  mode <- rep %% 3 != 0
  if (mode) tt <- tt[sort(sample(nrow(tt), floor(nrow(tt) * runif(1, 0.5, 0.85)))), ]
  if (sum(tt$OUT) < 2 || sum(tt$OUT == 0) < 1) next
  idx <- function(r) sum(as.numeric(r) * 2^((n - 1):0))
  on <- sapply(which(tt$OUT == 1), function(i) idx(tt[i, 1:n]))
  full <- expand.grid(rep(list(0:1), n)); allm <- sapply(seq_len(nrow(full)), function(i) idx(full[i, ])); seen <- sapply(seq_len(nrow(tt)), function(i) idx(tt[i, 1:n]))
  dc <- if (mode) setdiff(allm, seen) else integer(0)
  pistr <- function(s) { ch <- rep("-", n); for (tk in strsplit(s, "*", fixed = TRUE)[[1]]) { ng <- substr(tk, 1, 1) == "~"; ch[match(sub("~", "", tk), LETTERS)] <- if (ng) "0" else "1" }; paste(ch, collapse = "") }
  modtxt <- function(pis) paste(srt(vapply(pis, pistr, "")), collapse = "+")
  soltxt <- function(sol) { if (!is.list(sol)) sol <- list(sol); paste(srt(vapply(sol, modtxt, "")), collapse = ";") }
  chart <- function(m) modtxt(rownames(m$PIchart))
  a <- function(kind, de = rep(0, n)) c(kind, n, length(on), length(dc), on, dc, de)
  tbl <- truthTable(tt, outcome = "OUT", incl.cut = 1, show.cases = FALSE)
  m0 <- tryCatch(suppressWarnings(minimize(tbl, include = "", details = TRUE)), error = function(e) NULL)
  if (!is.null(m0) && length(m0$solution) > 0 && length(m0$solution) < 200) { add(a(0), soltxt(m0$solution)); add(a(3), chart(m0)) }
  if (!mode) next
  m1 <- tryCatch(suppressWarnings(minimize(tbl, include = "?", details = TRUE)), error = function(e) NULL)
  if (!is.null(m1) && length(m1$solution) > 0 && length(m1$solution) < 200) { add(a(1), soltxt(m1$solution)); add(a(4), chart(m1)) }
  for (rr in 1:2) {
    k <- sample(1:n, 1); vs <- sample(n, k); pol <- sample(1:2, k, TRUE); de <- rep(0, n); de[vs] <- pol
    des <- paste(ifelse(pol == 1, "~", ""), LETTERS[vs], sep = "", collapse = ",")
    m2 <- tryCatch(suppressWarnings(minimize(tbl, include = "?", dir.exp = des, details = TRUE)), error = function(e) NULL)
    if (is.null(m2) || is.null(m2$i.sol) || length(m2$i.sol) == 0 || length(m2$i.sol) > 60) next
    ent <- vapply(m2$i.sol, function(i) paste(modtxt(i$c.sol), modtxt(i$p.sol), soltxt(i$solution), sep = "|"), "")
    add(a(2, de), paste(srt(ent), collapse = "#"))
  }
}
emit("qca_min", "QCA", list(cases))
