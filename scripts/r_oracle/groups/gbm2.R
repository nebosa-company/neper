# gbm, second half of the oracle (kept apart so each JSON stays small): offsets, larger data sets, more seeds. The helpers and the case layout are those of gbm.R.
lines <- readLines(file.path(root, "scripts", "r_oracle", "groups", "gbm.R"))
idx <- grep("^cases <- list\\(\\)", lines)[1]
eval(parse(text = lines[1:(idx - 1)]))
cases <- list()
G <- function(g, outs) cases[[length(cases) + 1]] <<- gcases(g, outs)
std <- eval(parse(text = paste(lines[grep("^std <- function", lines):(grep("^stdm <- function", lines) - 1)], collapse = "\n")))
stdm <- eval(parse(text = paste(lines[grep("^stdm <- function", lines):(grep("^cat\\(\"gaussian", lines) - 1)], collapse = "\n")))
cat("offsets\n")
for (dd in c(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)) {
  pr <- if (dd == 7) 4 else if (dd == 5) 0.7 else 0
  nn <- if (dd == 9) 150 else 120
  G(gcfg(400 + dd, dd, n = nn, mono = 2, par = pr, fseed = 3 + dd), if (dd == 9) stdm(20, nrow = nn) else std(30, nrow = nn))
  G(gcfg(410 + dd, dd, n = nn, mono = 2, par = pr, bag = 1, d = 3, tf = 0.8, nt = 25, wflag = 1, fseed = 2), if (dd == 9) stdm(25, nrow = nn, tf = 0.8, bag = 1) else std(25, nrow = nn, tf = 0.8, bag = 1))
}
G(gcfg(421, 11, n = 150, nt = 25, mo = 3, bag = 0.6, mono = 2), std(25, nrow = 150, bag = 0.6))
G(gcfg(422, 10, n = 150, nt = 25, mo = 3, bag = 0.7, mono = 2, fseed = 4), std(25, nrow = 150, bag = 0.7))
emit("gbm2", c("gbm", "survival"), cases)
