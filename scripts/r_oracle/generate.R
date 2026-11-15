# Regenerates the R oracle goldens in tests/oracle/.
#
#   Rscript scripts/r_oracle/generate.R            every group in scripts/r_oracle/groups
#   Rscript scripts/r_oracle/generate.R special    only the named groups
#
# Packages a group needs are installed beforehand (install.packages(pkg, lib = dir)); point
# R_ORACLE_LIB at dir when it is not a default library.
#
# A group file builds `cases` with `case()` or `sweep()` and calls `emit(name, packages)`.
# Seeds are fixed inside each group, so two runs on the same R and package versions write
# the same bytes. A number is written with 17 significant digits so it reads back to the
# same double; NA, NaN, Inf and -Inf are strings because JSON has no spelling for them.

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."))
if (nzchar(Sys.getenv("R_ORACLE_LIB"))) .libPaths(c(Sys.getenv("R_ORACLE_LIB"), .libPaths()))
out_dir <- file.path(root, "tests", "oracle")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

num <- function(x) {
  if (is.na(x) && !is.nan(x)) return('"NA"')
  if (is.nan(x)) return('"NaN"')
  if (is.infinite(x)) return(if (x > 0) '"Inf"' else '"-Inf"')
  sprintf("%.17g", x)
}
str <- function(s) {
  s <- gsub("\\\\", "\\\\\\\\", s)
  s <- gsub('"', '\\\\"', s)
  for (i in 1:31) s <- gsub(intToUtf8(i), sprintf("\\u%04x", i), s, fixed = TRUE)
  paste0('"', s, '"')
}

# One check: `fn` names the Neper function the fixture dispatches on, `args` are its
# arguments, `want` is R's answer. `rel` and `abs` are the tolerance the comparison allows
# (either one is enough); both zero means exact.
case <- function(fn, args, want, rel = 1e-12, abs = 0, input = NULL) {
  list(fn = fn, args = as.numeric(args), want = if (is.character(want)) want else as.numeric(want), rel = rel, abs = abs, input = input)
}

# `f` over every row of a grid of arguments, one case per row.
sweep <- function(fn, f, grid, rel = 1e-12, abs = 0) {
  grid <- as.data.frame(grid)
  lapply(seq_len(nrow(grid)), function(i) {
    a <- unlist(grid[i, ], use.names = FALSE)
    case(fn, a, suppressWarnings(do.call(f, as.list(a))), rel, abs)
  })
}

emit <- function(name, packages = character(), cases) {
  cases <- unlist(cases, recursive = FALSE)
  if (!is.null(cases$fn)) stop("emit() wants a list of cases")
  pkgs <- vapply(packages, function(p) as.character(packageVersion(p)), "")
  meta <- paste0('{"r":', str(R.version.string),
                 ',"packages":{', if (length(pkgs)) paste(sprintf("%s:%s", str(names(pkgs)), str(pkgs)), collapse = ","), '}}')
  body <- vapply(cases, function(c) {
    if (is.character(c$want))
      return(sprintf('{"fn":%s,"args":[%s]%s,"text":%s}', str(c$fn), paste(vapply(c$args, num, ""), collapse = ","),
                     if (is.null(c$input)) "" else sprintf(',"in":[%s]', paste(vapply(c$input, str, ""), collapse = ",")), str(c$want)))
    sprintf('{"fn":%s,"args":[%s],"want":%s,"rel":%s,"abs":%s}', str(c$fn),
            paste(vapply(c$args, num, ""), collapse = ","), num(c$want), num(c$rel), num(c$abs))
  }, "")
  path <- file.path(out_dir, paste0(name, ".json"))
  writeLines(c(sprintf('{"group":%s,"meta":%s,"cases":[', str(name), meta),
               paste0(body, c(rep(",", length(body) - 1L), "")), "]}"), path, useBytes = TRUE)
  message(sprintf("%s: %d cases -> %s", name, length(body), path))
}

wanted <- commandArgs(TRUE)
for (f in sort(list.files(file.path(root, "scripts", "r_oracle", "groups"), "\\.R$", full.names = TRUE))) {
  if (length(wanted) == 0 || sub("\\.R$", "", basename(f)) %in% wanted) source(f, local = new.env(parent = globalenv()))
}
