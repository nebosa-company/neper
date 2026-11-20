# foreign::write.foreign for SAS (the data file, the code file) and abbreviate(). Frames are written as tests/oracle/data/wfs_<i>.spec in the layout of foreign_write.R
# (per column the name, the kind, the tab-joined levels and the tab-joined values). Cases "data" and "code" take args (i, variant) with variant 0 the default (V7 names), 1 validvarname
# "V6", 2 a libpath and a dataname; the answer is R's file as text (CR removed). "abbr" takes the minlength as its argument and the names as input; the answer is the abbreviations joined
# with "|". The first line of the code file carries the deparsed call, which the fixture reads from tests/oracle/data/wfs_<i>_<variant>.call.
suppressMessages(library(foreign))
cases <- list()
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
set.seed(20261120)
pool <- c("id", "age", "my var", "x-y", "a.b", "1st", "income", "group", "flag", "comment", "score", "height", "w t", "city", "tag#1", "price$", "e@mail",
          "long_variable_name_number_one", "annual_household_income_in_dollars", "number_of_children_under_18", "age_at_first_hospital_admission",
          "Region", "Q1.score", "Q2.score", "QuarterlyRevenue", "measurement_alpha_one", "measurement_alpha_two", "systolic_blood_pressure",
          "diastolic_blood_pressure", "TotalPopulation", "Smoking Status", "ever_married", "9lives", "region_code", "year_of_birth_estimate_value_x")
levpool <- c("low", "mid", "high", "a b", "say \"hi\"", "x,y", "z")
words <- function(n) vapply(seq_len(n), function(i) paste(sample(c(letters, "\"", ",", " "), sample(1:12, 1), replace = TRUE), collapse = ""), "")
mkcol <- function(kind, n) {
  na <- runif(n) < 0.1
  switch(as.character(kind),
    "0" = { x <- round(rnorm(n) * 10^sample(-3:6, 1), sample(0:6, 1)); x[sample(n, 1)] <- c(100000, 0.1 + 0.2, 1/3, 123456789.123456789, 1e-5, 1e15)[sample(6, 1)]; x[na] <- NA; x },
    "4" = { x <- sample(-100:1000, n, replace = TRUE); x[na] <- NA; x },
    "1" = { l <- sample(levpool, sample(2:4, 1)); x <- factor(sample(l, n, replace = TRUE), levels = l); x[na] <- NA; x },
    "5" = { l <- sample(levpool, sample(2:4, 1)); x <- factor(sample(l, n, replace = TRUE), levels = l, ordered = TRUE); x[na] <- NA; x },
    "3" = { x <- sample(c(TRUE, FALSE), n, replace = TRUE); x[na] <- NA; x },
    "2" = { x <- words(n); x[na] <- NA; x })
}
txt <- function(f) { b <- readBin(f, "raw", 1e6); b <- b[b != as.raw(13)]; rawToChar(b) }
i <- 0
while (i < 14) {
  n <- sample(3:8, 1); nc <- sample(c(3, 5, 8, 12), 1)
  nm <- sample(pool, nc)
  kinds <- sample(c(0, 4, 1, 5, 3, 2), nc, replace = TRUE)
  if (i %% 3 == 0) kinds[nc] <- 2
  if (i %% 4 == 1) kinds[1:2] <- c(2, 1)
  ok <- tryCatch({ suppressMessages({ foreign:::make.SAS.names(nm); v6 <- foreign:::make.SAS.names(nm, "V6"); fk <- kinds %in% c(1, 5); if (any(fk)) { foreign:::make.SAS.formats(v6[fk]); foreign:::make.SAS.formats(foreign:::make.SAS.names(nm)[fk]) } }); TRUE }, error = function(e) FALSE)
  if (!ok) next
  i <- i + 1
  cols <- lapply(seq_len(nc), function(j) mkcol(kinds[j], n))
  names(cols) <- nm
  df <- do.call(data.frame, c(cols, list(check.names = FALSE, stringsAsFactors = FALSE)))
  sp <- c(sprintf("%d %d", nc, n))
  for (j in seq_len(nc)) {
    x <- df[[j]]; k <- kinds[j]
    vals <- if (k == 2) ifelse(is.na(x), "<NA>", x) else if (k %in% c(1, 5)) ifelse(is.na(x), "NA", as.integer(x)) else if (k == 3) ifelse(is.na(x), "NA", as.integer(x)) else ifelse(is.na(x), "NA", sprintf("%.17g", x))
    sp <- c(sp, nm[j], as.character(k), if (k %in% c(1, 5)) paste(levels(x), collapse = "\t") else "", paste(vals, collapse = "\t"))
  }
  writeLines(sp, file.path(root, sprintf("tests/oracle/data/wfs_%d.spec", i)), useBytes = TRUE)
  for (v in 0:2) {
    dfile <- sprintf("tests/oracle/data/wfs_%d_%d.csv", i, v); cfile <- sprintf("tests/oracle/data/wfs_%d_%d.sas", i, v)
    cl <- switch(v + 1, quote(write.foreign(df, dfile, cfile, package = "SAS")),
                 quote(write.foreign(df, dfile, cfile, "SAS", validvarname = "V6")),
                 quote(write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata")))
    writeLines(deparse(cl)[1], file.path(root, sprintf("tests/oracle/data/wfs_%d_%d.call", i, v)))
    old <- setwd(root); suppressMessages(eval(cl)); setwd(old)
    cases[[length(cases) + 1]] <- case("data", c(i, v), txt(file.path(root, dfile)))
    cases[[length(cases) + 1]] <- case("code", c(i, v), txt(file.path(root, cfile)))
  }
}
# abbreviate() on its own, as write.foreign uses it: names with no blanks, vectors with duplicates and with names that collide once cut
ab <- list(c("measurement_alpha_one", "measurement_alpha_two", "measurement_beta_one"), c("alpha", "alpha", "beta"), c("Population", "PopulationDensity", "PopulationGrowth"),
           c("a_b_c_d_e_f", "q__w__e", "aeiouaeiou", "AEIOU", "rstuvwxyz", "income_2019", "income_2020", "income_2021"), c("x", "yy", "zzz"),
           sprintf("var_number_%02d", 1:12))
for (mn in c(1, 3, 4, 6, 8, 12, 32)) for (v in ab) {
  r <- tryCatch(paste(abbreviate(v, mn, named = FALSE), collapse = "|"), error = function(e) NULL)
  if (!is.null(r)) cases[[length(cases) + 1]] <- case("abbr", mn, r, input = v)
}
rn <- function() paste(sample(c(letters, LETTERS, "_", 0:9), sample(1:40, 1), replace = TRUE), collapse = "")
for (k in 1:40) {
  v <- vapply(1:sample(1:6, 1), function(z) rn(), ""); mn <- sample(c(2, 4, 6, 8, 10, 16), 1)
  r <- tryCatch(paste(abbreviate(v, mn, named = FALSE), collapse = "|"), error = function(e) NULL)
  if (!is.null(r)) cases[[length(cases) + 1]] <- case("abbr", mn, r, input = v)
}
emit("foreign_write_sas", "foreign", list(cases))
