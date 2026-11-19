# ncdf4 on netCDF classic files: the files tests/oracle/data/ncdf4_<i>.nc are written here by ncdf4. Cases take the variable name in "in":
# "ncn" (file, 0) the number of elements, "ncd" (file, dim index by the order of the dimensions in the file) the dimension length, "ncv" (file, flat index in file order, which is the R column-major order of the array) a value, "ncs" (file, 0) the sum
suppressMessages(library(ncdf4))
cases <- list()
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
set.seed(20261300)
for (i in 1:6) {
  nx <- sample(2:5, 1); ny <- sample(2:4, 1); nt <- sample(1:3, 1); unl <- i %% 2 == 1
  x <- ncdim_def("x", "m", seq_len(nx)); y <- ncdim_def("y", "m", seq_len(ny) * 2); tm <- ncdim_def("time", "days", seq_len(nt), unlim = unl)
  prec <- c("double", "float", "integer", "short", "double", "integer")[i]
  v1 <- ncvar_def("temp", "K", list(x, y, tm), -999, prec = prec); v2 <- ncvar_def("id", "", list(x), -1L, prec = "integer"); v3 <- ncvar_def("g", "", list(x, y), NA, prec = "float"); v4 <- ncvar_def("sh", "", list(y), -1L, prec = "short")
  f <- file.path(root, sprintf("tests/oracle/data/ncdf4_%d.nc", i)); nc <- nc_create(f, list(v1, v2, v3, v4))
  a1 <- array(if (prec %in% c("integer", "short")) as.numeric(sample(-50:100, nx * ny * nt, TRUE)) else round(rnorm(nx * ny * nt, 5, 3), 3), c(nx, ny, nt))
  a2 <- sample(-5:20, nx); a3 <- matrix(round(runif(nx * ny, -4, 4) * 4) / 4, nx, ny); a4 <- sample(-100:100, ny)
  ncvar_put(nc, v1, a1); ncvar_put(nc, v2, a2); ncvar_put(nc, v3, a3); ncvar_put(nc, v4, a4); ncatt_put(nc, 0, "title", "t"); nc_close(nc)
  nc <- nc_open(f)
  for (d in names(nc$dim)) cases[[length(cases) + 1]] <- case("ncd", c(i, match(d, c("x", "y", "time"))), nc$dim[[d]]$len, rel = 0, abs = 0, input = d)
  for (vn in c("temp", "id", "g", "sh", "x", "y", "time")) {
    v <- ncvar_get(nc, vn, raw_datavals = TRUE); flat <- as.vector(v); if (length(flat) == 0) next
    cases[[length(cases) + 1]] <- case("ncn", c(i, 0), length(flat), rel = 0, abs = 0, input = vn)
    cases[[length(cases) + 1]] <- case("ncs", c(i, 0), sum(flat), rel = 1e-9, abs = 1e-9, input = vn)
    for (k in unique(c(1, length(flat), ceiling(length(flat) / 2)))) cases[[length(cases) + 1]] <- case("ncv", c(i, k - 1), flat[k], rel = 1e-9, abs = 1e-9, input = vn)
  }
  nc_close(nc)
}
emit("ncdf4", "ncdf4", list(cases))
