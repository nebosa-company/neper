# foreign::read.epiinfo of fixed-width EpiInfo .REC files written here (tests/oracle/data/epiinfo_<i>.rec, epiinfo_e<i>.rec for the error cases).
#   args (file, col, opt) with opt = deleted * 4 + guess.broken.dates * 2 + lower.case.names, deleted 0 = FALSE, 1 = TRUE, 2 = NA; thisyear is "2020".
#   fn: nrow, ncol, ndel (the deleted attribute's sum), kind (0 number, 1 logical, 2 Date, 3 text), nna, sum, wsum (weighted by the 1-based row), nhash and chash
#   (names and prompts, each byte weighted by its position), and "eerr" (1 when read.epiinfo stops with an error; args (file, 0, 0)).
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) if (length(want) != 1 || is.na(want)) stop(paste("NA want", fn, paste(args, collapse = ","))) else cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
set.seed(20261230)
pad <- function(x, n) formatC(x, width = -n, flag = "-")
rpad <- function(x, n) formatC(x, width = n)
rnd_date <- function(us, yd) {
  d <- as.Date("1990-01-01") + sample(0:12000, 1)
  if (us) f <- "%m/%d/" else f <- "%d/%m/"
  paste0(format(d, f), if (yd == 4) format(d, "%Y") else format(d, "%y"))
}
mkfile <- function(path, vars, nrec, marked = FALSE) {
  # vars: list of list(name, type, len, prompt)
  total <- sum(sapply(vars, function(v) v$len))
  stopifnot(total %% 78 != 0)
  hdr <- sapply(vars, function(v) paste0(pad(sprintf("%s 0 0 0 0 0 %d %d 0", v$name, v$type, v$len), 45), v$prompt))
  recs <- character(nrec)
  for (r in seq_len(nrec)) {
    cells <- sapply(vars, function(v) {
      L <- v$len
      if (L == 0) return("")
      miss <- runif(1) < 0.15
      s <- if (miss) strrep(" ", L) else switch(as.character(v$type),
        "0" = , "6" = , "12" = , "13" = if (runif(1) < 0.1) pad("abc", L) else rpad(format(round(rnorm(1) * 10^sample(0:3, 1), sample(0:2, 1)), nsmall = 0, trim = TRUE), L),
        "5" = pad(sample(c("Y", "N", "x"), 1, prob = c(.45, .45, .1)), L),
        "11" = , "16" = pad(rnd_date(FALSE, if (L == 8) 2 else 4), L),
        "2" = , "10" = pad(rnd_date(TRUE, if (L == 8) 2 else 4), L),
        "17" = pad(paste0(sample(LETTERS, 1), sprintf("%03d", sample(0:999, 1))), L),
        pad(paste(sample(letters, L %/% 2, replace = TRUE), collapse = ""), L))
      s <- substr(s, 1, L)
      s
    })
    rec <- paste0(paste(cells, collapse = ""), if (runif(1) < 0.2) "?" else " ")
    recs[r] <- rec
  }
  lines <- character(0)
  for (rec in recs) lines <- c(lines, substring(rec, seq(1, nchar(rec), 78), pmin(seq(78, nchar(rec) + 77, 78), nchar(rec))))
  writeLines(c(sprintf("%d  EpiInfo", length(vars)), hdr, lines), path)
}
V <- function(name, type, len, prompt = "") list(name = name, type = type, len = len, prompt = prompt)
files <- list(
  list(vars = list(V("ID", 0, 4, "Identifier"), V("SEX", 5, 1, "Male? (Y/N)"), V("NAME", 1, 12, "Last name"), V("WEIGHT", 0, 6, "Weight kg"), V("LABELX", 1, 0, "section break"),
                   V("DOB", 11, 10, "Date of birth"), V("SNDX", 17, 5, "Soundex")), n = 9),
  list(vars = list(V("#ID", 12, 5, "Auto id"), V("#VISIT", 10, 10, "Visit date US"), V("#SHORT", 11, 8, "Short date"), V("#NOYR", 11, 5, "Day/month"), V("#FLAG", 5, 1, "Flag"), V("#VAL", 6, 7, "Value")), n = 8),
  list(vars = list(V("_A", 0, 3, "a"), V("_B", 2, 8, "US short date"), V("_C", 10, 5, "US day"), V("_D", 16, 10, "EU auto date"), V("_E", 13, 4, "other numeric"), V("_F", 1, 20, "text twenty")), n = 10),
  list(vars = list(V("A1", 1, 30, "first text"), V("A2", 1, 30, "second text"), V("A3", 0, 8, "number"), V("A4", 5, 1, "yn"), V("A5", 1, 15, "third text")), n = 7),
  list(vars = list(V("R1", 1, 40, "long"), V("R2", 1, 40, "long2"), V("R3", 0, 10, "n10"), V("R4", 11, 10, "date"), V("R5", 17, 5, "sx"), V("R6", 5, 1, "yn")), n = 6)
)
summarize <- function(i, path) {
  for (del in 0:2) for (guess in 0:1) for (lower in 0:1) {
    opt <- del * 4 + guess * 2 + lower
    d <- suppressWarnings(read.epiinfo(path, read.deleted = c(FALSE, TRUE, NA)[del + 1], guess.broken.dates = guess == 1, thisyear = "2020", lower.case.names = lower == 1))
    add("nrow", c(i, 0, opt), nrow(d)); add("ncol", c(i, 0, opt), ncol(d))
    add("ndel", c(i, 0, opt), if (is.null(attr(d, "deleted"))) 0 else sum(attr(d, "deleted")))
    for (j in seq_along(d)) {
      x <- d[[j]]
      kind <- if (inherits(x, "Date")) 2 else if (is.logical(x)) 1 else if (is.numeric(x)) 0 else 3
      if (kind == 3) { x <- as.character(x); v <- sapply(x, function(z) if (is.na(z)) NA_real_ else sum(as.numeric(utf8ToInt(z)))) } else v <- as.numeric(x)
      ok <- !is.na(v)
      add("kind", c(i, j - 1, opt), kind); add("nna", c(i, j - 1, opt), sum(!ok))
      add("sum", c(i, j - 1, opt), sum(v[ok])); add("wsum", c(i, j - 1, opt), sum(v[ok] * seq_along(v)[ok]))
      nm <- names(d)[j]; pr <- attr(d, "prompts")[[j]]
      add("nhash", c(i, j - 1, opt), sum(as.numeric(utf8ToInt(nm)) * seq_len(nchar(nm))))
      add("chash", c(i, j - 1, opt), if (nchar(pr) == 0) 0 else sum(as.numeric(utf8ToInt(pr)) * seq_len(nchar(pr))))
    }
  }
}
for (i in seq_along(files)) {
  path <- file.path(root, sprintf("tests/oracle/data/epiinfo_%d.rec", i))
  mkfile(path, files[[i]]$vars, files[[i]]$n)
  summarize(i, path)
}
# handwritten files: file 6 reads numbers as R's as.numeric does, file 7 dates (invalid days, leap days, two-digit years, month 13, blanks)
hw <- function(i, vars, rows) {
  path <- file.path(root, sprintf("tests/oracle/data/epiinfo_%d.rec", i))
  hdr <- sapply(vars, function(v) paste0(pad(sprintf("%s 0 0 0 0 0 %d %d 0", v$name, v$type, v$len), 45), v$prompt))
  writeLines(c(sprintf("%d  EpiInfo", length(vars)), hdr, rows), path)
  summarize(i, path)
}
hw(6, list(V("N", 0, 6, "num"), V("T", 1, 3, "txt")),
   c("    .5 a ", "  5.e1bb ", "   1e3cc ", "  0x1Add ", "    +5ee ", "   Infff ", "   NaNgg ", "    NAhh ", "   1 2ii ", "   1d2jj ", "  -0.5kk?", "     .ll ", "     -mm ", "   1e-3  "))
hw(7, list(V("D", 11, 10, "eu"), V("U", 10, 10, "us"), V("S", 11, 8, "short"), V("Q", 2, 5, "us5")),
   c("29/02/200002/29/200029/02/9902/29", "29/02/190002/29/190031/04/0502/30", "31/12/199912/31/199931/12/0012/31", "01/13/200013/01/200000/01/6812/32", "1 /1 /200 1 /1 /200 5/ 6/69 1 /1 ", "5/6/2001  6/5/2001  15/06/2602/05", "          ", "15/06/200106/15/200115/06/7007/04",
     "31/12/9999  /  /    ab/cd/efgh01/01/00 12", "15/06/200106/15/2001    /68  01/01"))
# long prompts: R keeps columns 46 to 126 of the header line (81 characters), so a longer label is cut there
hw(8, list(V("A", 0, 3, paste(rep("abcdefghi", 10), collapse = "")), V("B", 1, 3, paste(rep("xyz", 27), collapse = "")), V("C", 0, 3, paste(rep("w", 82), collapse = ""))),
   c("  1  1  2", " 12  0 33", "  3  1  4"))
# error cases
errs <- list(
  c("0  EpiInfo", "A 0 0 0 0 0 0 3 0", "123 "),
  c("1  EpiInfo", "A 0 0 0 0 0 0 3 0"),
  c("1  EpiInfo", "A 0 0 0 0 0 0 3", "123 "),
  c("1  EpiInfo", "A 0 0 0 0 0 zz 3 0", "123 "),
  c("EpiInfo", "A 0 0 0 0 0 0 3 0", "123 "),
  c("2  EpiInfo", "A 0 0 0 0 0 0 3 0", "B 0 0 0 0 0 0 3 0", "123 "),
  c("1  EpiInfo", "A 0 0 0 0 0 0 3 0", "123 ", "456 ")
)
for (i in seq_along(errs)) {
  path <- file.path(root, sprintf("tests/oracle/data/epiinfo_e%d.rec", i))
  writeLines(errs[[i]], path)
  r <- tryCatch(suppressWarnings(read.epiinfo(path)), error = function(e) NULL)
  if (is.null(r) || is.data.frame(r)) add("eerr", c(i, 0, 0), as.numeric(is.null(r)))
  if (is.data.frame(r)) { add("enrow", c(i, 0, 0), nrow(r)); add("encol", c(i, 0, 0), ncol(r)) }
}
emit("foreign_epiinfo", "foreign", list(cases))
