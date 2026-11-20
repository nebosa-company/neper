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
rs <- function(v) if (is.list(v)) sum(vapply(unclass(v), rs, 0)) else if (is.character(v)) sum(vapply(v[!is.na(v)], cu, 0)) else sum(as.numeric(unclass(v)), na.rm = TRUE)
rw <- function(v) if (is.list(v)) sum(vapply(unclass(v), rw, 0)) else { x <- if (is.character(v)) vapply(ifelse(is.na(v), "", v), cu, 0) else as.numeric(unclass(v)); ok <- !is.na(v); sum(x[ok] * seq_along(x)[ok]) }
rn <- function(v) if (is.list(v)) sum(vapply(unclass(v), rn, 0)) else sum(is.na(v))
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
    add("len", c(i, k - 1), length(v)); add("sum", c(i, k - 1), rs(v)); add("wsum", c(i, k - 1), rw(v)); add("nna", c(i, k - 1), rn(v))
    lv <- levels(v); add("nlev", c(i, k - 1), length(lv)); add("levs", c(i, k - 1), if (length(lv)) sum(vapply(lv, cu, 0)) else 0)
    d <- attr(v, "dim"); add("ndim", c(i, k - 1), length(d)); add("dimprod", c(i, k - 1), if (is.null(d)) 0 else prod(d))
    add("nnames", c(i, k - 1), length(names(v))); add("elh", c(i, k - 1), hasht(names(v)))
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
      add("elen", c(i, k - 1), length(v)); add("esum", c(i, k - 1), rs(v)); add("ewsum", c(i, k - 1), rw(v)); add("enna", c(i, k - 1), rn(v))
    }
  }
}
emit("foreign_sdump", "foreign", list(cases))
