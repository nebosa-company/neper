# viridisLite::viridis and RColorBrewer::brewer.pal. A viridis case is
# (n, alpha, begin, end, direction, option 1..8 = A..H) and answers the colours joined by ",";
# a brewer case is fn "brewer:<name>", args (n), the same answer. brewer.pal answers the 3 or
# the largest palette outside its range, with a warning, and those sizes are probed too.
library(viridisLite)
library(RColorBrewer)

joined <- function(x) paste(x, collapse = ",")

viridis_case <- function(n, alpha, begin, end, direction, opt) {
  want <- suppressWarnings(viridis(n, alpha, begin, end, direction, LETTERS[opt]))
  case("viridis", c(n, alpha, begin, end, direction, opt), joined(want))
}

sweep_n <- unlist(lapply(1:8, function(opt) lapply(c(1:64, 100, 127, 128, 129, 200, 255, 256), function(n)
  viridis_case(n, 1, 0, 1, 1, opt))), recursive = FALSE)

grid <- expand.grid(n = c(1, 2, 3, 5, 10, 31), alpha = c(1, 0.5, 0.2, 0), range = 1:5, direction = c(1, -1), opt = 1:8)
ranges <- list(c(0, 1), c(0.2, 0.8), c(0.5, 0.5), c(1, 0), c(0.1, 0.3))
sweep_params <- lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]
  r <- ranges[[g$range]]
  viridis_case(g$n, g$alpha, r[1], r[2], g$direction, g$opt)
})

info <- brewer.pal.info
brewer <- unlist(lapply(rownames(info), function(name) lapply(1:(info[name, "maxcolors"] + 1), function(n)
  case(paste0("brewer:", name), n, joined(suppressWarnings(brewer.pal(n, name)))))), recursive = FALSE)

emit("palette", c("viridisLite", "RColorBrewer"), list(sweep_n, sweep_params, brewer))
