# foreign::data.restore of S-PLUS data.dump files (text, oldStyle) written here: tests/oracle/data/sdump_<i>.txt, and sdump_e<i>.txt for the error cases.
#   args (file, object) with the object's 0-based position in the file. fn: nobj; len (length); sum and wsum (sum of the values, and of each leaf vector's values times
#   their 1-based position; a character counts its code units, a factor its codes; NA left out); nna; nlev and levs (the number and code units of the levels); ndim and
#   dimprod (the dim attribute's length and product); nnames and elh (the names' number and sum of code units times position); nhash (the object's own name);
#   "eerr" (1 when data.restore stops with an error; args (file, 0)).
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) if (length(want) != 1 || is.na(want)) stop(paste("NA want", fn, paste(args, collapse = ","))) else cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
set.seed(20261232)
cu <- function(s) sum(as.numeric(utf8ToInt(s)))
hasht <- function(nm) if (length(nm) == 0) 0 else sum(vapply(seq_along(nm), function(i) cu(nm[i]) * i, 0))
# the dump: name, code, length, then the values (N for NA) or the elements
em <- function(name, v) {
  if (is.factor(v)) return(c(name, "structure", "3", em(".Data", as.integer(v)), em(".Label", levels(v)), em("class", "factor")))
  if (is.data.frame(v)) {
    cols <- unlist(lapply(seq_along(v), function(j) em(names(v)[j], v[[j]])))
    return(c(name, "structure", "3", c(".Data", "list", as.character(length(v)), cols), em("row.names", row.names(v)), em("class", "data.frame")))
  }
  if (is.matrix(v)) return(c(name, "structure", "2", em(".Data", as.vector(v)), em(".Dim", dim(v))))
  if (is.list(v)) return(c(name, "list", as.character(length(v)), unlist(lapply(seq_along(v), function(j) em(if (is.null(names(v))) "" else names(v)[j], v[[j]])))))
  s <- if (is.logical(v)) ifelse(is.na(v), "N", as.character(as.integer(v))) else ifelse(is.na(v), "N", as.character(v))
  c(name, if (is.logical(v)) "logical" else if (is.integer(v)) "integer" else if (is.character(v)) "character" else sample(c("double", "numeric", "single"), 1), as.character(length(v)), s)
}
rty <- function(v) if (is.complex(v)) 1 else if (is.name(v)) 2 else if (is.null(v)) 3 else if (is.call(v)) 4 else if (is.function(v)) 5 else if (is.expression(v)) 6 else 0
rs <- function(v) if (rty(v) >= 2) 0 else if (is.complex(v)) sum(Re(v[!is.na(v)])) else if (is.list(v)) sum(vapply(unclass(v), rs, 0)) else if (is.character(v)) sum(vapply(v[!is.na(v)], cu, 0)) else sum(as.numeric(unclass(v)), na.rm = TRUE)
ri <- function(v) if (rty(v) >= 2) 0 else if (is.complex(v)) sum(Im(v[!is.na(v)])) else if (is.list(v)) sum(vapply(unclass(v), ri, 0)) else 0
rw <- function(v) if (rty(v) >= 2) 0 else if (is.list(v)) sum(vapply(unclass(v), rw, 0)) else { x <- if (is.character(v)) vapply(ifelse(is.na(v), "", v), cu, 0) else if (is.complex(v)) Re(v) else as.numeric(unclass(v)); ok <- !is.na(v); sum(x[ok] * seq_along(x)[ok]) }
rn <- function(v) if (rty(v) >= 2) 0 else if (is.list(v)) sum(vapply(unclass(v), rn, 0)) else sum(is.na(v))
# every summary of one object, as cases (i, k): `pre` is "" for the dumps proper and "e" for the hand-written ones
summ <- function(i, k, v, pre = "") {
  a <- c(i, k)
  add(paste0(pre, "len"), a, length(v)); add(paste0(pre, "sum"), a, rs(v)); add(paste0(pre, "wsum"), a, rw(v)); add(paste0(pre, "nna"), a, rn(v))
  add(paste0(pre, "ty"), a, rty(v)); add(paste0(pre, "isum"), a, ri(v))
  add(paste0(pre, "nnames"), a, length(names(v))); add(paste0(pre, "elh"), a, hasht(names(v)))
}
ndig <- function(x) round(x, sample(0:5, 1))
words <- function(n) vapply(seq_len(n), function(i) paste(sample(letters, sample(1:9, 1), replace = TRUE), collapse = ""), "")
objs_for <- function() {
  n <- sample(5:9, 1)
  objs <- list()
  for (k in 1:n) {
    nm <- paste0(sample(letters, 1), "obj", k)
    objs[[nm]] <- switch(sample(1:9, 1),
      { x <- ndig(rnorm(sample(1:8, 1)) * 10^sample(-2:5, 1)); x[sample(length(x), 1)] <- NA; x },
      sample(c(-50:200, NA), sample(1:9, 1), replace = TRUE),
      sample(c(TRUE, FALSE, NA), sample(1:7, 1), replace = TRUE),
      { x <- words(sample(1:6, 1)); x[sample(length(x), 1)] <- NA; x },
      factor(sample(c("a", "bc", "def", "x y"), 7, replace = TRUE)),
      matrix(ndig(rnorm(12) * 100), sample(c(2, 3, 4), 1)),
      list(ndig(rnorm(3)), words(2), TRUE),
      list(p = ndig(rnorm(4)), q = list(r = 1:3, s = c("u", "v")), t = factor(c("lo", "hi", "lo"))),
      data.frame(f = factor(sample(c("m", "n"), 4, replace = TRUE)), i = c(NA, sample(1:9, 3)), d = ndig(rnorm(4) * 10), l = c(TRUE, NA, FALSE, TRUE), s = words(4), stringsAsFactors = FALSE))
  }
  objs
}
for (i in 1:8) {
  objs <- objs_for()
  lines <- unlist(lapply(seq_along(objs), function(k) em(names(objs)[k], objs[[k]])))
  path <- file.path(root, sprintf("tests/oracle/data/sdump_%d.txt", i))
  writeLines(lines, path)
  e <- new.env()
  suppressWarnings(data.restore(path, env = e))
  add("nobj", c(i, 0), length(ls(e)))
  for (k in seq_along(objs)) {
    v <- get(names(objs)[k], e)
    summ(i, k - 1, v)
    lv <- levels(v); add("nlev", c(i, k - 1), length(lv)); add("levs", c(i, k - 1), if (length(lv)) sum(vapply(lv, cu, 0)) else 0)
    d <- attr(v, "dim"); add("ndim", c(i, k - 1), length(d)); add("dimprod", c(i, k - 1), if (is.null(d)) 0 else prod(d))
    add("nhash", c(i, k - 1), sum(as.numeric(utf8ToInt(names(objs)[k])) * seq_len(nchar(names(objs)[k]))))
  }
}
# the dump R ships (tests/dumpdata), a hand-written one with every number format, short atomic values at the end of the file, and the error cases
H <- c("a", "integer", "3", "1", "N", "3")
errs <- list(
  c("x"),
  c("x", "numeric", "zz", "1"),
  c("x", "bogus", "1", "1"),
  c("x", "structure", "2", ".Data", "numeric", "3", "1", "2", "3", ".Dim", "integer", "2", "2", "2"),
  c("x", "list", "2", "", "numeric", "1", "5"),
  c("", "numeric", "1", "5"),
  c("x", "numeric", "3", "1", "2"),
  c("x", "numeric", "2", "1e3", "0x1F", "y", "integer", "3", "3.9", "-2.5", "1e2"),
  c("x", "structure", "1", ".Dim", "integer", "1", "3"),
  character(0),
  c("x", "list", "0", "y", "list", "1", "", "numeric", "1", "4"),
  c("x", "numeric", "3", "Inf", "7", "N", "z", "logical", "4", "1", "0", "2", "N")
)
# the modes that build something other than a vector: A atoms (name, mode, lines), K objects holding kids
A <- function(nm, code, ...) { x <- c(...); c(nm, code, as.character(length(x)), if (length(x)) as.character(x)) }
K <- function(nm, code, ...) { kk <- list(...); c(nm, code, as.character(length(kk)), unlist(kk)) }
n1 <- A("a", "numeric", "1", "2"); u1 <- A("", "numeric", "1", "3"); u2 <- A("", "integer", "4", "5", "N", "7")
errs <- c(errs, list(
  A("z", "complex", "1+2i", "3", "N", "2i", "-1.5e2-3i", "1+i", " 4 ", "1e2+3.5e1i", "inf", "1+2", "0x10", "1e+2i", "-i", "i"),
  A("z", "complex"), A("z", "complex", "7"),
  A("s", "name", "foo", "bar"), A("s", "name", "N"), A("s", "name"), A("s", "name", ""), A("s", "name", "N", ""),
  K("n", "NULL"), K("n", "NULL", A("a", "numeric", "5")), c(K("x", "NULL"), A("y", "numeric", "1")),
  A("m", "missing", "1"), A("m", "missing"), A("m", "missing", "x", "y"),
  K("f", "function", n1, u1), K("f", "function", u1, u1), K("f", "function"), K("f", "function", A("x", "numeric", "5")),
  K("f", "function", n1, A("b", "character", "z"), K("", "list", u1, u2)), K("f", "function", n1, K("", "NULL"), u1), K("f", "function", A("a", "numeric", "1"), K("", "NULL")),
  K("c", "if", n1, u1), K("c", "(", u1), K("c", "{"), K("c", "<-", u1, A("v", "numeric", "2", "1", "2"), u2), K("c", "S.call", K("", "NULL"), u1),
  K("c", "call(...)", n1, u1), K("c", "call(...)"), K("c", "call(...)", K("", "NULL"), u1), K("c", "call(...)", K("l", "list", n1)),
  K("c", "internal", u1), K("c", "internal"), K("c", "internal", K("", "NULL")),
  K("c", "comment", n1), K("c", "comment.expression", K("", "NULL"), u1, u2), K("c", "comment.expression"), K("c", "comment.expression", K("", "NULL")),
  K("e", "expression", n1, u1, K("", "NULL"), u2), K("e", "expression"), K("e", "expression", u1),
  K("c", "call", u1, u2), K("c", "call", n1, u2), K("c", "call"), K("c", "call", K("", "NULL")),
  K("c", "vector", n1, u1), K("c", "string", n1), K("c", "unknown", u1), K("c", "[", n1), K("c", " ", n1), K("c", "addop"), K("c", "end.of.file", u1), K("c", "comment(leftover)", n1),
  K("l", "list", K("", "NULL"), u2), K("l", "list", K("", "NULL"), K("", "NULL"), u2, K("b", "NULL"), u1),
  K("l", "list", u1, K("", "NULL"), u2, n1), K("l", "list", n1, K("a2", "list", u1, K("z", "NULL")), K("", "if", u1)),
  K("l", "list", A("a", "complex", "1+1i", "2i"), K("f", "function", n1, u1), K("q", "call", u1, u1), K("e", "expression", u1), A("s", "name", "w")),
  K("l", "list", K("a", "comment", u1), K("", "comment"), u1),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "6", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3", "N", "5", "6"), A(".Tsp", "numeric", "2", "4", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3.5", "4")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "5", "1", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3", "0")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "N", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3", "1", "9")),
  K("t", "structure", A(".Data", "numeric"), A(".Tsp", "numeric", "1", "3", "1")),
  K("t", "structure", A(".Data", "integer", "4", "5", "6", "7"), A(".Tsp", "numeric", "1990", "1990.75", "4")),
  K("t", "structure", A(".Data", "character", "a", "bc"), A(".Tsp", "numeric", "1", "5", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3", "4", "5", "6"), A(".Dim", "integer", "2", "2", "3"), A(".Tsp", "numeric", "1", "6", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3.00001", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "0.5", "2.5", "1")),
  K("t", "structure", A(".Tsp", "numeric", "1", "3", "1"), A(".Data", "numeric", "1", "2", "3")),
  # .Tsp tolerances: each pair sits on either side of a ts() threshold (cycle rounding, tsp consistency, start after end, frequency snapping)
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3.001", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3.05", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3.000005", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "3.00002", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "201.0005", "0.01")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "201.000009", "0.01")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "201.00002", "0.01")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "3.5", "3", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "3", "2.9999999", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "3", "2.999995", "1")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "3", "3.000005", "10")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "1001", "1.000009")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "1001", "1.000011")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "1001", "1.000001")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "251", "4.000001")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "251", "4.00002")),
  K("t", "structure", A(".Data", "numeric", "1", "2", "3"), A(".Tsp", "numeric", "1", "1001", "0.999991")),
  K("t", "structure"), K("t", "structure", K(".Dimnames", "list")), K("t", "structure", A("class", "character", "foo")), K("t", "structure", A(".Dim", "integer", "1", "3")),
  K("t", "structure", A(".Label", "character", "a"))
))
for (i in seq_along(errs)) {
  path <- file.path(root, sprintf("tests/oracle/data/sdump_e%d.txt", i))
  writeLines(errs[[i]], path)
  e <- new.env()
  r <- tryCatch({ suppressWarnings(data.restore(path, env = e)); TRUE }, error = function(err) FALSE)
  add("eerr", c(i, 0), as.numeric(!r))
  if (r) {
    nm <- sort(ls(e)); add("enobj", c(i, 0), length(nm))
    for (k in seq_along(nm)) {
      v <- get(nm[k], e)
      summ(i, k - 1, v, "x")
    }
  }
}
emit("foreign_sdump", "foreign", list(cases))
