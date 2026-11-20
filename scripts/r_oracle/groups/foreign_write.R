# foreign::write.foreign for SPSS and Stata. Each frame i is written as tests/oracle/data/wf_<i>.spec (the layout is read by the fixture: per column the name, the kind,
# the tab-joined levels and the tab-joined values; kinds 0 double, 1 factor, 2 character, 3 logical, 4 integer, 5 ordered factor; NA is "NA", "<NA>" for a character),
# and R's own outputs as wf_<i>_spss.csv/.sps and wf_<i>_stata.csv/.do. Cases: args (i, package, part) with package 0 SPSS and 1 Stata, part 0 the data file and 1 the
# code file; "len" is the byte length and "hash" the sum of byte * (1-based position).
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
set.seed(20261231)
pool <- c("id", "age", "my var", "x-y", "a.b", "1st", "income", "group", "flag", "comment", "score", "height", "w t", "long_variable_name_number_one", "city", "tag#1", "price$", "e@mail")
levpool <- c("low", "mid", "high", "a b", "say \"hi\"", "x,y", "z")
words <- function(n) vapply(seq_len(n), function(i) paste(sample(letters, sample(1:12, 1), replace = TRUE), collapse = ""), "")
mkcol <- function(kind, n) {
  na <- runif(n) < 0.1
  switch(as.character(kind),
    "0" = { x <- round(rnorm(n) * 10^sample(-3:6, 1), sample(0:6, 1)); x[sample(n, 1)] <- c(100000, 0.1 + 0.2, 1/3, 123456789.123456789, 1e-5, 1e15, 12345678901234567)[sample(7, 1)]; x[na] <- NA; x },
    "4" = { x <- sample(-100:1000, n, replace = TRUE); x[na] <- NA; x },
    "1" = { l <- sample(levpool, sample(2:4, 1)); x <- factor(sample(l, n, replace = TRUE), levels = l); x[na] <- NA; x },
    "5" = { l <- sample(levpool, sample(2:4, 1)); x <- factor(sample(l, n, replace = TRUE), levels = l, ordered = TRUE); x[na] <- NA; x },
    "3" = { x <- sample(c(TRUE, FALSE), n, replace = TRUE); x[na] <- NA; x },
    "2" = { x <- words(n); x[na] <- NA; x })
}
for (i in 1:10) {
  n <- sample(4:9, 1); nc <- sample(c(3, 5, 8, 12, 14), 1)
  nm <- sample(pool, nc)
  kinds <- sample(c(0, 4, 1, 5, 3, 2), nc, replace = TRUE)
  if (i %% 2 == 1) kinds[1:2] <- c(2, 1)
  if (i %% 3 == 0) kinds <- sample(c(0, 2), nc, replace = TRUE)
  cols <- lapply(seq_len(nc), function(j) mkcol(kinds[j], n))
  names(cols) <- nm
  df <- do.call(data.frame, c(cols, list(check.names = FALSE, stringsAsFactors = FALSE)))
  sp <- c(sprintf("%d %d", nc, n))
  for (j in seq_len(nc)) {
    x <- df[[j]]
    k <- kinds[j]
    vals <- if (k == 2) ifelse(is.na(x), "<NA>", x) else if (k %in% c(1, 5)) ifelse(is.na(x), "NA", as.integer(x)) else if (k == 3) ifelse(is.na(x), "NA", as.integer(x)) else ifelse(is.na(x), "NA", sprintf("%.17g", x))
    sp <- c(sp, nm[j], as.character(k), if (k %in% c(1, 5)) paste(levels(x), collapse = "\t") else "", paste(vals, collapse = "\t"))
  }
  writeLines(sp, file.path(root, sprintf("tests/oracle/data/wf_%d.spec", i)), useBytes = TRUE)
  for (p in 0:1) {
    pk <- c("SPSS", "Stata")[p + 1]; ext <- c("sps", "do")[p + 1]
    dfile <- sprintf("tests/oracle/data/wf_%d_%s.csv", i, tolower(pk)); cfile <- sprintf("tests/oracle/data/wf_%d_%s.%s", i, tolower(pk), ext)
    # the code file names the data file as given, so R is run again from root with the relative path
    old <- setwd(root); suppressWarnings(write.foreign(df, dfile, cfile, package = pk)); setwd(old)
    for (part in 0:1) {
      b <- readBin(file.path(root, if (part == 0) dfile else cfile), "raw", 1e6); b <- b[b != as.raw(13)]
      add("len", c(i, p, part), length(b)); add("hash", c(i, p, part), sum(as.numeric(as.integer(b)) * seq_along(b)))
    }
  }
}
emit("foreign_write", "foreign", list(cases))
