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
cvo <- function(nt, nrow = 120) c(list(list(12, 0), list(12, nt - 1), list(12, nt %/% 2), list(14, 2), list(15, 0), list(15, 1), list(16, 0), list(16, 7)), lapply(c(0, 20, 50, 80), function(i) list(13, i)))
sm <- function(nt, nrow, tf = 1, bag = 0.5) c(list(list(1, 0), list(1, nrow - 1), list(1, nrow %/% 2), list(2, 0), list(2, nt - 1), list(9, 0), list(6, 0), list(5, 0, nt), list(5, 1, nt), list(5, 2, nt), list(7, 0, nt), list(7, 7, nt)),
  if (tf < 1) list(list(3, nt - 1), list(10, 0)), if (bag < 1) list(list(4, nt - 1), list(11, 0)),
  lapply(c(20, 21, 22, 23, 25, 27), function(f) list(f, 0, nt)), lapply(c(20, 21, 22, 23, 25, 27), function(f) list(f, 1, 1)))
G(gcfg(501, 0, n = 3000, nt = 40, bag = 0.5, d = 3, mo = 10, fseed = 1), sm(40, 3000))
G(gcfg(502, 1, n = 2000, nt = 40, bag = 0.6, d = 2, mo = 10, tf = 0.8, fseed = 2), sm(40, 2000, tf = 0.8, bag = 0.6))
G(gcfg(503, 2, n = 2500, nt = 40, bag = 0.5, d = 4, mo = 20, wflag = 1, fseed = 3), sm(40, 2500))
G(gcfg(504, 8, n = 2000, nt = 40, bag = 0.5, d = 2, mo = 10, fseed = 4), sm(40, 2000))
G(gcfg(505, 5, n = 2000, nt = 30, bag = 0.5, par = 0.3, mo = 10, fseed = 5), sm(30, 2000))
G(gcfg(506, 7, n = 2000, nt = 30, bag = 0.7, par = 4, mo = 10, fseed = 6, p = 5), sm(30, 2000, bag = 0.7))
G(gcfg(507, 9, n = 900, nt = 15, bag = 0.5, mo = 10, fseed = 7), stdm(15, nrow = 900, nodes = 4))
G(gcfg(508, 11, n = 1500, nt = 20, bag = 0.6, mo = 10, fseed = 8), sm(20, 1500))
G(gcfg(509, 0, n = 2000, nt = 30, bag = 0.5, cv = 3, mo = 10, fseed = 9), c(sm(30, 2000), cvo(30, 2000)))
G(gcfg(510, 3, n = 2000, nt = 40, bag = 0.5, mo = 10, na = 1, fseed = 10), sm(40, 2000))
set.seed(77)
for (k in 1:60) {
  dd <- c(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 10)[k %% 14 + 1]
  nn <- if (dd == 9) 150 else sample(c(80, 120, 200), 1)
  if (dd >= 10) nn <- 150
  G(gcfg(600 + k, dd, n = nn, nt = 40, d = sample(1:3, 1), mo = sample(c(3, 5, 8), 1), bag = sample(c(0.5, 0.65, 0.8), 1), sh = sample(c(0.05, 0.1, 0.3), 1), par = if (dd == 5) 0.4 else if (dd == 7) 3 else 0, p = sample(3:4, 1), fseed = k), if (dd == 9) stdm(40, nrow = nn, nodes = 4) else sm(40, nn))
}
emit("gbm2", c("gbm", "survival"), cases)
